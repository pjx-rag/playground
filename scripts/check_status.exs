alias Playground.{Repo, Files.File, EventLog}
import Ecto.Query

file_id = 35628

file = Repo.get!(File, file_id)

IO.puts("\n📄 File #{file_id}: #{file.name}")
IO.puts("   Processing Status: #{file.processing_status}")
IO.puts("   Sync Status: #{file.sync_status}")
IO.puts("   Attempts: #{file.processing_attempt || 0}")
IO.puts("   Updated: #{file.updated_at}")

awaiting = Repo.all(from f in File, where: f.processing_status == "awaiting_analysis", select: {f.id, f.name})
IO.puts("\n⏳ Files awaiting analysis (#{length(awaiting)}):")
Enum.each(awaiting, fn {id, name} -> IO.puts("   [#{id}] #{name}") end)

analyzing = Repo.all(from f in File, where: f.processing_status == "analyzing", select: {f.id, f.name})
IO.puts("\n🔄 Files analyzing (#{length(analyzing)}):")
Enum.each(analyzing, fn {id, name} -> IO.puts("   [#{id}] #{name}") end)

events = Repo.all(from e in EventLog, where: e.file_id == ^file_id, order_by: [desc: e.inserted_at], limit: 5, select: {e.event_type, e.inserted_at})
IO.puts("\n📋 Recent events for file #{file_id}:")
Enum.each(events, fn {type, time} -> IO.puts("   #{time} - #{type}") end)

IO.puts("")
