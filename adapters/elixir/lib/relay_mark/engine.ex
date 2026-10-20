defmodule RelayMark.Engine do
  @moduledoc false
  # Calls into the RelayMark engine NIF. Inputs and results cross as JSON;
  # inputs above the threshold run on a dirty CPU scheduler, so a large paper
  # never holds a normal scheduler.

  @dirty_bytes 4_096

  @spec call(String.t(), binary(), map()) :: {:ok, binary()} | {:error, String.t()}
  def call(job, input, options \\ %{}) when is_binary(input) do
    options = if options == %{}, do: "", else: Jason.encode!(options)

    if byte_size(input) + byte_size(options) > @dirty_bytes,
      do: RelayMark.Native.run_dirty(job, input, options),
      else: RelayMark.Native.run(job, input, options)
  end

  @doc "A job on a JSON value whose result is JSON."
  @spec json(String.t(), term(), map()) :: {:ok, term()} | {:error, String.t()}
  def json(job, value, options \\ %{}) do
    with {:ok, input} <- encode(value), {:ok, output} <- call(job, input, options) do
      {:ok, Jason.decode!(output)}
    end
  end

  @doc "A job on a JSON value whose result is text."
  @spec text(String.t(), term(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def text(job, value, options \\ %{}) do
    with {:ok, input} <- encode(value), do: call(job, input, options)
  end

  @doc "A job on source text whose result is JSON."
  @spec source(String.t(), String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def source(job, source, options \\ %{}) when is_binary(source) do
    with {:ok, output} <- call(job, source, options), do: {:ok, Jason.decode!(output)}
  end

  defp encode(value) do
    case Jason.encode(value) do
      {:ok, json} -> {:ok, json}
      {:error, _} -> {:error, "Input is not JSON"}
    end
  end
end
