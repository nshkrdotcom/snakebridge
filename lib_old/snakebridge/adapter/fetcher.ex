defmodule SnakeBridge.Adapter.Fetcher do
  @moduledoc """
  Fetches Python libraries from Git repositories or PyPI.

  Handles:
  - Git URL parsing and cloning
  - PyPI package → GitHub URL resolution
  - Python project detection (setup.py, pyproject.toml, etc.)
  - Library metadata extraction
  """

  require Logger

  @python_libs_dir "pythonLibs"

  @type fetch_result :: %{
          name: String.t(),
          path: String.t(),
          source: :git | :pypi,
          url: String.t(),
          python_module: String.t(),
          is_python: boolean(),
          metadata: map()
        }

  @doc """
  Fetches a Python library from a URL or package name.

  ## Parameters

  - `source` - Git URL or PyPI package name
  - `opts` - Options
    - `:force` - Re-clone even if exists (default: false)
    - `:libs_dir` - Custom libs directory (default: "pythonLibs")

  ## Returns

  `{:ok, fetch_result}` or `{:error, reason}`
  """
  @spec fetch(String.t(), keyword()) :: {:ok, fetch_result()} | {:error, term()}
  def fetch(source, opts \\ []) do
    libs_dir = Keyword.get(opts, :libs_dir, @python_libs_dir)
    force? = Keyword.get(opts, :force, false)

    with :ok <- ensure_libs_dir(libs_dir),
         {:ok, parsed} <- parse_source(source),
         {:ok, path} <- clone_or_use_existing(parsed, libs_dir, force?),
         {:ok, metadata} <- detect_python_project(path) do
      {:ok,
       %{
         name: parsed.name,
         path: path,
         source: parsed.type,
         url: parsed.url,
         python_module: metadata.module_name || parsed.name,
         is_python: metadata.is_python,
         metadata: metadata
       }}
    end
  end

  @doc """
  Ensures the pythonLibs directory exists.
  """
  @spec ensure_libs_dir(String.t()) :: :ok | {:error, term()}
  def ensure_libs_dir(libs_dir) do
    case File.mkdir_p(libs_dir) do
      :ok ->
        Logger.debug("Ensured libs directory: #{libs_dir}")
        :ok

      {:error, reason} ->
        {:error, {:mkdir_failed, libs_dir, reason}}
    end
  end

  @doc """
  Parses a source string (URL or package name) into structured data.
  """
  @spec parse_source(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_source(source) do
    cond do
      github_url?(source) ->
        parse_github_url(source)

      gitlab_url?(source) ->
        parse_gitlab_url(source)

      git_url?(source) ->
        parse_generic_git_url(source)

      pypi_name?(source) ->
        resolve_pypi_to_git(source)

      true ->
        {:error, {:invalid_source, source}}
    end
  end

  @doc """
  Detects if a directory contains a Python project and extracts metadata.
  """
  @spec detect_python_project(String.t()) :: {:ok, map()} | {:error, term()}
  def detect_python_project(path) do
    cond do
      File.exists?(Path.join(path, "pyproject.toml")) ->
        parse_pyproject_toml(path)

      File.exists?(Path.join(path, "setup.py")) ->
        parse_setup_py(path)

      File.exists?(Path.join(path, "setup.cfg")) ->
        parse_setup_cfg(path)

      has_python_files?(path) ->
        {:ok, %{is_python: true, module_name: nil, version: nil, description: nil}}

      true ->
        {:error, {:not_python_project, path}}
    end
  end

  # Private functions - URL parsing

  defp github_url?(url) do
    String.contains?(url, "github.com")
  end

  defp gitlab_url?(url) do
    String.contains?(url, "gitlab.com")
  end

  defp git_url?(url) do
    String.starts_with?(url, "git@") or
      String.starts_with?(url, "https://") or
      String.starts_with?(url, "http://") or
      String.ends_with?(url, ".git")
  end

  defp pypi_name?(source) do
    # Simple package name: alphanumeric, hyphens, underscores
    Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9_-]*$/, source)
  end

  defp parse_github_url(url) do
    # Handle various GitHub URL formats
    regex = ~r{github\.com[:/](?<owner>[^/]+)/(?<repo>[^/\.]+)(?:\.git)?(?:/.*)?$}

    case Regex.named_captures(regex, url) do
      %{"owner" => owner, "repo" => repo} ->
        clean_url = "https://github.com/#{owner}/#{repo}.git"
        {:ok, %{type: :git, url: clean_url, name: repo, owner: owner}}

      nil ->
        {:error, {:invalid_github_url, url}}
    end
  end

  defp parse_gitlab_url(url) do
    regex = ~r{gitlab\.com[:/](?<owner>[^/]+)/(?<repo>[^/\.]+)(?:\.git)?(?:/.*)?$}

    case Regex.named_captures(regex, url) do
      %{"owner" => owner, "repo" => repo} ->
        clean_url = "https://gitlab.com/#{owner}/#{repo}.git"
        {:ok, %{type: :git, url: clean_url, name: repo, owner: owner}}

      nil ->
        {:error, {:invalid_gitlab_url, url}}
    end
  end

  defp parse_generic_git_url(url) do
    # Extract repo name from URL
    name =
      url
      |> String.split("/")
      |> List.last()
      |> String.replace(~r/\.git$/, "")

    {:ok, %{type: :git, url: url, name: name, owner: nil}}
  end

  defp resolve_pypi_to_git(package_name) do
    # Try to fetch PyPI metadata to find GitHub URL
    Logger.info("Resolving PyPI package to Git URL: #{package_name}")

    pypi_url = "https://pypi.org/pypi/#{package_name}/json"

    case fetch_json(pypi_url) do
      {:ok, data} ->
        find_github_from_pypi(data, package_name)

      {:error, _} ->
        # Fallback: assume GitHub with same name
        Logger.warning("Could not fetch PyPI metadata, assuming GitHub: #{package_name}")

        {:ok,
         %{
           type: :pypi,
           url: "https://github.com/#{package_name}/#{package_name}.git",
           name: package_name,
           owner: nil
         }}
    end
  end

  defp find_github_from_pypi(data, package_name) do
    urls = get_in(data, ["info", "project_urls"]) || %{}
    home_page = get_in(data, ["info", "home_page"])

    github_url =
      Enum.find_value(urls, fn {_key, url} ->
        if github_url?(url || ""), do: url
      end) || (github_url?(home_page || "") && home_page)

    if github_url do
      case parse_github_url(github_url) do
        {:ok, parsed} -> {:ok, Map.put(parsed, :type, :pypi)}
        error -> error
      end
    else
      {:error, {:no_github_url, package_name}}
    end
  end

  # Private functions - Cloning

  defp clone_or_use_existing(parsed, libs_dir, force?) do
    target_path = Path.join(libs_dir, parsed.name)

    cond do
      File.dir?(target_path) and not force? ->
        Logger.info("Using existing clone: #{target_path}")
        {:ok, target_path}

      File.dir?(target_path) and force? ->
        Logger.info("Removing existing clone for re-fetch: #{target_path}")
        File.rm_rf!(target_path)
        do_clone(parsed.url, target_path)

      true ->
        do_clone(parsed.url, target_path)
    end
  end

  defp do_clone(url, target_path) do
    Logger.info("Cloning #{url} to #{target_path}")

    args = ["clone", "--depth", "1", url, target_path]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, target_path}

      {output, code} ->
        {:error, {:clone_failed, url, code, output}}
    end
  end

  # Private functions - Python project detection

  defp parse_pyproject_toml(path) do
    toml_path = Path.join(path, "pyproject.toml")

    case File.read(toml_path) do
      {:ok, content} ->
        # Simple TOML parsing for key fields
        name = extract_toml_value(content, ~r/name\s*=\s*"([^"]+)"/)
        version = extract_toml_value(content, ~r/version\s*=\s*"([^"]+)"/)
        description = extract_toml_value(content, ~r/description\s*=\s*"([^"]+)"/)

        {:ok,
         %{
           is_python: true,
           module_name: name && String.replace(name, "-", "_"),
           version: version,
           description: description,
           project_type: :pyproject
         }}

      {:error, reason} ->
        {:error, {:read_failed, toml_path, reason}}
    end
  end

  defp parse_setup_py(path) do
    setup_path = Path.join(path, "setup.py")

    case File.read(setup_path) do
      {:ok, content} ->
        name = extract_setup_value(content, ~r/name\s*=\s*['"]([^'"]+)['"]/)
        version = extract_setup_value(content, ~r/version\s*=\s*['"]([^'"]+)['"]/)

        {:ok,
         %{
           is_python: true,
           module_name: name && String.replace(name, "-", "_"),
           version: version,
           description: nil,
           project_type: :setup_py
         }}

      {:error, reason} ->
        {:error, {:read_failed, setup_path, reason}}
    end
  end

  defp parse_setup_cfg(path) do
    cfg_path = Path.join(path, "setup.cfg")

    case File.read(cfg_path) do
      {:ok, content} ->
        name = extract_ini_value(content, "name")
        version = extract_ini_value(content, "version")

        {:ok,
         %{
           is_python: true,
           module_name: name && String.replace(name, "-", "_"),
           version: version,
           description: nil,
           project_type: :setup_cfg
         }}

      {:error, reason} ->
        {:error, {:read_failed, cfg_path, reason}}
    end
  end

  defp has_python_files?(path) do
    case File.ls(path) do
      {:ok, files} ->
        Enum.any?(files, fn f ->
          String.ends_with?(f, ".py") or
            (File.dir?(Path.join(path, f)) and has_python_files?(Path.join(path, f)))
        end)

      _ ->
        false
    end
  end

  # Helper functions

  defp extract_toml_value(content, regex) do
    case Regex.run(regex, content) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp extract_setup_value(content, regex) do
    case Regex.run(regex, content) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp extract_ini_value(content, key) do
    regex = ~r/#{key}\s*=\s*(.+)/

    case Regex.run(regex, content) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  defp fetch_json(url) do
    # Use httpc from Erlang stdlib (no deps needed)
    :inets.start()
    :ssl.start()

    url_charlist = String.to_charlist(url)

    case :httpc.request(:get, {url_charlist, []}, [{:timeout, 10_000}], []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        Jason.decode(to_string(body))

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
