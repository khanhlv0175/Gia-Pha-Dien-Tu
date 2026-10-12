-- ============================================================
-- 0005 — Nhật ký kiểm toán và thông báo do trigger sinh ra
-- ============================================================

-- Ghi TÊN trường thay đổi, không ghi giá trị (tránh log thành nơi rò rỉ SĐT/email...).
CREATE FUNCTION log_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_new JSONB;
    v_old JSONB;
    v_row JSONB;
    v_fields TEXT[];
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_row := to_jsonb(OLD);
    ELSE
        v_row := to_jsonb(NEW);
    END IF;

    IF TG_OP = 'UPDATE' THEN
        v_new := to_jsonb(NEW);
        v_old := to_jsonb(OLD);
        SELECT coalesce(array_agg(k ORDER BY k), '{}') INTO v_fields
          FROM jsonb_object_keys(v_new) AS k
         WHERE k NOT IN ('updated_at') AND v_new -> k IS DISTINCT FROM v_old -> k;
        IF cardinality(v_fields) = 0 THEN
            RETURN NEW;
        END IF;
    END IF;

    INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, changed_fields)
    VALUES (
        (SELECT id FROM profiles WHERE id = auth.uid()),
        CASE TG_OP WHEN 'INSERT' THEN 'CREATE' WHEN 'UPDATE' THEN 'UPDATE' ELSE 'DELETE' END,
        TG_TABLE_NAME,
        coalesce(v_row ->> 'handle', v_row ->> 'id'),
        v_fields
    );

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER audit_people AFTER INSERT OR UPDATE OR DELETE ON people
    FOR EACH ROW EXECUTE FUNCTION log_audit();
CREATE TRIGGER audit_people_private AFTER INSERT OR UPDATE OR DELETE ON people_private
    FOR EACH ROW EXECUTE FUNCTION log_audit();
CREATE TRIGGER audit_families AFTER INSERT OR UPDATE OR DELETE ON families
    FOR EACH ROW EXECUTE FUNCTION log_audit();
CREATE TRIGGER audit_profiles AFTER INSERT OR UPDATE OR DELETE ON profiles
    FOR EACH ROW EXECUTE FUNCTION log_audit();
CREATE TRIGGER audit_contributions AFTER UPDATE ON contributions
    FOR EACH ROW EXECUTE FUNCTION log_audit();
CREATE TRIGGER audit_invite_links AFTER INSERT OR DELETE ON invite_links
    FOR EACH ROW EXECUTE FUNCTION log_audit();

-- ── Thông báo ──────────────────────────────────────────────
CREATE FUNCTION notify_contribution_reviewed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') AND NEW.author_id IS NOT NULL THEN
        INSERT INTO notifications (user_id, type, title, message, link_url)
        VALUES (
            NEW.author_id,
            'SYSTEM',
            CASE NEW.status WHEN 'approved' THEN 'Đóng góp của bạn đã được duyệt'
                            ELSE 'Đóng góp của bạn bị từ chối' END,
            coalesce(NEW.field_label, NEW.field_name) || ' — ' || coalesce(NEW.person_name, NEW.person_handle)
                || coalesce(E'\nGhi chú: ' || NEW.admin_note, ''),
            '/people/' || NEW.person_handle
        );
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER contributions_notify AFTER UPDATE OF status ON contributions
    FOR EACH ROW EXECUTE FUNCTION notify_contribution_reviewed();

CREATE FUNCTION notify_new_event() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO notifications (user_id, type, title, message, link_url)
    SELECT p.id, 'NEW_EVENT', 'Sự kiện mới: ' || NEW.title,
           to_char(NEW.start_at, 'DD/MM/YYYY HH24:MI') || coalesce(' · ' || NEW.location, ''),
           '/events/' || NEW.id
      FROM profiles p
     WHERE p.role IN ('admin', 'member') AND p.id IS DISTINCT FROM NEW.creator_id;
    RETURN NEW;
END;
$$;
CREATE TRIGGER events_notify AFTER INSERT ON events
    FOR EACH ROW EXECUTE FUNCTION notify_new_event();
