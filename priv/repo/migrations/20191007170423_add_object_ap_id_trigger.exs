defmodule Pleroma.Repo.Migrations.AddObjectApIdTrigger do
  use Ecto.Migration

  def change do
    execute("""
    CREATE OR REPLACE FUNCTION set_ap_id()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $BODY$
    BEGIN
      NEW.ap_id = NEW.data->>'id';
      RETURN NEW;
    END
    $BODY$;
    """)

    execute("""
    CREATE TRIGGER object_ap_id_extraction
    BEFORE INSERT OR UPDATE
    ON objects
    FOR EACH ROW
    EXECUTE PROCEDURE set_ap_id();
    """)
  end
end
