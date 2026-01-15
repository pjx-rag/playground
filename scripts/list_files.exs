alias Playground.{Repo, Files.File}
import Ecto.Query

IO.puts("\n📁 All files in database:")
IO.puts("=" <> String.duplicate("=", 80))

files = Repo.all(
  from f in File,
  order_by: [desc: f.updated_at],
  limit: 20,
  select: {f.id, f.name, f.processing_status, f.sync_status, f.mime_type}
)

case files do
  [] ->
    IO.puts("   No files found in database")
  files ->
    Enum.each(files, fn {id, name, proc_status, sync_status, mime} ->
      IO.puts("   [#{id}] #{name}")
      IO.puts("       Processing: #{proc_status} | Sync: #{sync_status} | Type: #{mime}")
    end)
end

# Check for PDFs specifically
pdfs = Repo.all(
  from f in File,
  where: f.mime_type == "application/pdf",
  select: {f.id, f.name, f.processing_status}
)

IO.puts("\n📄 PDF files:")
IO.puts("=" <> String.duplicate("=", 80))

case pdfs do
  [] ->
    IO.puts("   No PDF files found")
  pdfs ->
    Enum.each(pdfs, fn {id, name, status} ->
      IO.puts("   [#{id}] #{name} - #{status}")
    end)
end

IO.puts("")
