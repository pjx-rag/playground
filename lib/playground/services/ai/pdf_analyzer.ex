defmodule Playground.Services.AI.PdfAnalyzer do
  @moduledoc """
  Analyzes PDF files using vision AI via OpenRouter API.

  Sends the entire PDF as a multimodal input (PDF file + prompt) to AI which:
  - Extracts and converts all text content from the PDF
  - Describes all images/charts/diagrams inline where they appear
  - Categorizes the document based on content

  Returns complete text ready for chunking with image descriptions embedded.
  """

  require Logger
  import Ecto.Query
  alias Playground.Repo
  alias Playground.Files.Category
  alias Playground.Settings
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.Context

  @doc """
  Analyzes PDF content with AI vision model using ReqLLM structured output.

  ## Parameters

    - `pdf_binary` - Raw PDF file content as binary
    - `opts` - Optional keyword list (currently unused but reserved for future options)

  ## Returns

      {:ok, %{
        category_id: 1,
        content: "Complete text with inline image descriptions..."
      }}

  The `content` field contains the full document text with image descriptions
  embedded inline, ready for chunking.

  ## Example

      {:ok, analysis} = PdfAnalyzer.analyze(pdf_binary)
  """
  def analyze(pdf_binary, _opts \\ []) when is_binary(pdf_binary) do
    Logger.info("Starting PDF analysis", pdf_size: byte_size(pdf_binary))

    model = Settings.get_app_setting_value("pdf_analysis_model", "google/gemini-2.0-flash-001")
    Logger.info("Retrieved model setting", model: model)

    with {:ok, categories} <- fetch_categories(),
         _ = Logger.info("Fetched categories", count: length(categories)),
         {:ok, schema} <- build_schema(),
         {:ok, system_prompt} <- build_system_prompt(categories),
         _ = Logger.info("Built system prompt", prompt_length: String.length(system_prompt)),
         {:ok, response} <- call_llm(model, system_prompt, pdf_binary, schema) do
      {:ok, response}
    else
      {:error, reason} ->
        Logger.error("PDF analysis failed", error: inspect(reason, pretty: true))
        {:error, reason}
    end
  end

  defp fetch_categories do
    Logger.debug("Fetching categories from database")

    categories =
      Repo.all(
        from c in Category,
          select: %{id: c.id, name: c.name, instructions: c.instructions},
          order_by: c.display_order
      )

    Logger.debug("Categories retrieved",
      count: length(categories),
      ids: Enum.map(categories, & &1.id)
    )

    if Enum.empty?(categories) do
      Logger.error("No categories found in database - categories table may be empty")
    end

    {:ok, categories}
  end

  defp build_schema do
    schema = [
      category_id: [
        type: :integer,
        required: true,
        doc: "The ID of the most appropriate category for this document"
      ],
      content: [
        type: :string,
        required: true,
        doc:
          "Complete document text with inline image descriptions. Describe all images, charts, diagrams where they appear in the text."
      ]
    ]

    {:ok, schema}
  end

  defp build_system_prompt(categories) do
    category_list =
      categories
      |> Enum.map(fn cat ->
        "- ID #{cat.id}: #{cat.name} - #{cat.instructions || "No instructions"}"
      end)
      |> Enum.join("\n")

    prompt = """
    You are analyzing a PDF document for a RAG (Retrieval-Augmented Generation) system.

    Your tasks:
    1. Extract ALL text content from the PDF
    2. For every image, chart, diagram, or photo you encounter, describe it in detail INLINE where it appears
    3. Categorize the document using the most appropriate category ID from the list below

    Available categories:
    #{category_list}

    Output requirements:
    - category_id: Choose the single best category ID based on the document content and category instructions
    - content: Complete text with inline image descriptions like "[Image: Bar chart showing quarterly revenue growth from Q1 to Q4 2023, with values increasing from $1M to $2.5M]"
    - Make image descriptions detailed enough to be useful for semantic search
    - Preserve document structure (headings, paragraphs, etc.)
    - Do NOT include any preamble or explanation, just the document content
    """

    {:ok, prompt}
  end

  defp call_llm(model, system_prompt, pdf_binary, schema) do
    Logger.debug("Building multimodal message",
      pdf_size: byte_size(pdf_binary),
      prompt_length: String.length(system_prompt)
    )

    # Build multimodal messages using ReqLLM's ContentPart API
    messages = [
      Context.system(system_prompt),
      Context.user([
        ContentPart.text("Please analyze this PDF document and extract its content."),
        ContentPart.file(pdf_binary, "document.pdf", "application/pdf")
      ])
    ]

    model_spec = "openrouter:#{model}"

    Logger.info("Calling AI for PDF analysis",
      model: model,
      model_spec: model_spec
    )

    opts = [
      temperature: 0.3,
      max_tokens: 16000,
      receive_timeout: 300_000
    ]

    case ReqLLM.generate_object(model_spec, messages, schema, opts) do
      {:ok, %ReqLLM.Response{object: %{"category_id" => category_id, "content" => content}}} ->
        result = %{category_id: category_id, content: content}
        validated_result = validate_category(result)
        {:ok, validated_result}

      {:ok, %ReqLLM.Response{object: nil, message: message} = response} ->
        # Model returned empty object - check message content
        Logger.error("ReqLLM returned nil object",
          message: inspect(message),
          usage: inspect(response.usage)
        )
        {:error, :empty_response}

      {:ok, %ReqLLM.Response{error: error}} when not is_nil(error) ->
        Logger.error("ReqLLM returned error", error: inspect(error))
        {:error, error}

      {:error, reason} ->
        Logger.error("ReqLLM.generate_object failed", error: inspect(reason, pretty: true))
        {:error, reason}
    end
  end

  defp validate_category(%{category_id: category_id} = result) do
    # Check if category exists
    category_exists = Repo.exists?(from c in Category, where: c.id == ^category_id)

    if category_exists do
      result
    else
      Logger.warning("Invalid category_id from AI",
        category_id: category_id,
        defaulting_to: "general"
      )

      # Default to "general" category
      general_id = Repo.one!(from c in Category, where: c.slug == "general", select: c.id)
      %{result | category_id: general_id}
    end
  end
end
