defmodule Playground.Repo.Migrations.AddChunksSearchVectorTrigger do
  use Ecto.Migration

  def up do
    execute """
    CREATE FUNCTION chunks_update_search_vector() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'INSERT' OR NEW.content IS DISTINCT FROM OLD.content THEN
        NEW.search_vector := to_tsvector('pg_catalog.english', NEW.content);
      END IF;
      RETURN NEW;
    END
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER chunks_search_vector_update
    BEFORE INSERT OR UPDATE ON chunks
    FOR EACH ROW EXECUTE FUNCTION chunks_update_search_vector();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS chunks_search_vector_update ON chunks;"
    execute "DROP FUNCTION IF EXISTS chunks_update_search_vector();"
  end
end
