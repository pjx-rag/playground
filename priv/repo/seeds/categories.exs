alias Playground.Repo
alias Playground.Files.Category

# Seed initial document categories with optimized chunking strategies

categories = [
  %{
    name: "Technical Documentation",
    slug: "technical_documentation",
    description: "API docs, system architecture guides, developer documentation",
    instructions: "Look for: code examples, API endpoints, system diagrams, technical specifications, developer guides, SDK documentation, configuration files, or architectural overviews. Common markers: function signatures, HTTP methods, data schemas, technical jargon.",
    chunk_size: 1500,
    chunk_overlap: 200,
    color: "#3B82F6",
    icon: "code-bracket",
    display_order: 1
  },
  %{
    name: "Business Report",
    slug: "business_report",
    description: "Quarterly reports, market analysis, white papers",
    instructions: "Look for: executive summaries, financial metrics, market trends, competitive analysis, KPIs, revenue/growth data, strategic initiatives, or business forecasts. Common markers: charts/graphs, quarterly data, percentage changes, market share statistics.",
    chunk_size: 1000,
    chunk_overlap: 150,
    color: "#10B981",
    icon: "chart-bar",
    display_order: 2
  },
  %{
    name: "Academic Paper",
    slug: "academic_paper",
    description: "Research papers, journal articles, scientific publications",
    instructions: "Look for: abstract, methodology, literature review, research findings, citations, hypothesis, experimental results, peer-reviewed content, or academic references. Common markers: DOI, journal citations, research methodology sections, statistical analysis.",
    chunk_size: 1200,
    chunk_overlap: 200,
    color: "#8B5CF6",
    icon: "academic-cap",
    display_order: 3
  },
  %{
    name: "Presentation",
    slug: "presentation",
    description: "Slide decks, pitch presentations, training materials",
    instructions: "Look for: slide-based layout, bullet points, large headings, presenter notes, talking points, visual diagrams, or pitch decks. Common markers: slide numbers, minimal text per section, call-to-action statements, brand messaging.",
    chunk_size: 800,
    chunk_overlap: 50,
    color: "#F59E0B",
    icon: "presentation-chart-bar",
    display_order: 4
  },
  %{
    name: "Financial Document",
    slug: "financial_document",
    description: "Financial statements, invoices, tax documents",
    instructions: "Look for: balance sheets, income statements, cash flow, invoices, tax forms, accounting records, financial ratios, or audit reports. Common markers: currency symbols, accounting terms (debit/credit), fiscal periods, line items with amounts.",
    chunk_size: 1000,
    chunk_overlap: 100,
    color: "#059669",
    icon: "currency-dollar",
    display_order: 5
  },
  %{
    name: "Legal Contract",
    slug: "legal_contract",
    description: "Agreements, terms of service, legal policies",
    instructions: "Look for: terms and conditions, clauses, parties involved, legal obligations, signatures, effective dates, liability sections, or governing law statements. Common markers: 'whereas', 'hereby agrees', numbered clauses, legal terminology.",
    chunk_size: 800,
    chunk_overlap: 100,
    color: "#DC2626",
    icon: "scale",
    display_order: 6
  },
  %{
    name: "Marketing Material",
    slug: "marketing_material",
    description: "Brochures, product sheets, case studies, campaigns",
    instructions: "Look for: product features, benefits, customer testimonials, case studies, brand messaging, value propositions, or promotional content. Common markers: persuasive language, customer quotes, product imagery descriptions, CTAs.",
    chunk_size: 800,
    chunk_overlap: 150,
    color: "#EC4899",
    icon: "megaphone",
    display_order: 7
  },
  %{
    name: "General",
    slug: "general",
    description: "Uncategorized or mixed-content documents",
    instructions: "Use this category when the document doesn't clearly fit any other category, contains mixed content types, or lacks distinctive characteristics of the specialized categories.",
    chunk_size: 1000,
    chunk_overlap: 200,
    color: "#6B7280",
    icon: "document-text",
    display_order: 99
  }
]

Enum.each(categories, fn category_attrs ->
  %Category{}
  |> Category.changeset(category_attrs)
  |> Repo.insert!(
    on_conflict: {:replace, [:description, :instructions, :chunk_size, :chunk_overlap, :color, :icon, :display_order]},
    conflict_target: :slug
  )
end)

IO.puts("✓ Seeded #{length(categories)} document categories")
