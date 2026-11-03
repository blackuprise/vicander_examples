defmodule TodoApp.ArchitectureTest do
  @moduledoc """
  The layering rules, checked on the source (the call graph itself is enforced at compile time by
  `boundary`, see the layer modules):

    * `domain` depends on nothing of the app outside itself
    * `application` depends on `domain`, never on `infrastructure`
    * `infrastructure` implements the domain's ports
    * `interface` (the MCP server) calls the application and reads the domain; nothing depends on it
    * every file holds exactly one module, at the path its name gives

  This reads the code as text: cheap, and it also covers docs and strings.
  """
  use ExUnit.Case, async: true

  @root "lib/todo_app"

  defp files(layer), do: Path.wildcard("#{@root}/#{layer}/**/*.ex")
  defp read(file), do: File.read!(file)

  defp violations(layer, forbidden) do
    for file <- files(layer),
        source = read(file),
        namespace <- forbidden,
        source =~ ~r/TodoApp\.#{namespace}\b/,
        do: "#{file} mentions TodoApp.#{namespace}"
  end

  @layers ~w(domain application infrastructure interface)

  test "there are files in every layer" do
    for layer <- @layers do
      assert files(layer) != [], "no files found in #{layer}"
    end
  end

  test "the domain depends on neither the application nor the infrastructure" do
    assert violations("domain", ["Application", "Infrastructure", "Interface"]) == []
  end

  test "the application layer depends on the domain, not on the infrastructure" do
    assert violations("application", ["Infrastructure", "Interface"]) == []
  end

  test "the interface calls the application and the domain, never the infrastructure" do
    assert violations("interface", ["Infrastructure"]) == []
  end

  test "nothing depends on the interface" do
    assert violations("infrastructure", ["Interface"]) == []
  end

  test "every module lives in the namespace of its layer" do
    for layer <- @layers, file <- files(layer) do
      for [_, name] <- Regex.scan(~r/^defmodule\s+(\S+)\s+do/m, read(file)) do
        assert String.starts_with?(name, "TodoApp.#{String.capitalize(layer)}."),
               "#{file} defines #{name}, which is not in TodoApp.#{String.capitalize(layer)}"
      end
    end
  end

  test "every file holds exactly one module, at the path its name gives" do
    for file <- Path.wildcard("#{@root}/**/*.ex") do
      modules = for [_, name] <- Regex.scan(~r/^defmodule\s+(\S+)\s+do/m, read(file)), do: name

      assert [name] = modules, "#{file} defines #{length(modules)} modules: #{inspect(modules)}"
      assert file == "lib/" <> Macro.underscore(name) <> ".ex"
    end
  end

  test "nothing is left directly under todo_app/ outside the layers and the boot module" do
    # `TodoApp.Boot` is the composition root: the one module that knows every layer.
    allowed = Enum.map(@layers, &"#{@root}/#{&1}.ex") ++ ["#{@root}/boot.ex"]
    assert Enum.sort(Path.wildcard("#{@root}/*.ex")) == Enum.sort(allowed)
  end

  describe "sub-domains" do
    # A sub-domain is an aggregate root (`domain/<name>.ex`) and its folder (`domain/<name>/`).
    defp sub_domains do
      "#{@root}/domain/*.ex"
      |> Path.wildcard()
      |> Enum.map(&Path.basename(&1, ".ex"))
      |> Enum.sort()
    end

    test "the sub-domains are the aggregates" do
      assert sub_domains() == ["todo_list", "user"]
    end

    # Directories only: a trailing-slash wildcard would also return files.
    defp folders(path) do
      "#{path}/*"
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()
    end

    test "every domain folder belongs to an aggregate root next to it" do
      assert folders("#{@root}/domain") == sub_domains()
    end

    test "the aggregate root is named after its folder" do
      for sub <- sub_domains() do
        assert File.read!("#{@root}/domain/#{sub}.ex") =~
                 "defmodule TodoApp.Domain.#{Macro.camelize(sub)} do"
      end
    end

    test "commands, queries, handlers and projections live in the folder of their sub-domain" do
      for kind <- ~w(commands queries handlers projections) do
        subs = folders("#{@root}/application/#{kind}")

        assert subs != [], "no sub-domain folders under application/#{kind}"
        assert Enum.all?(subs, &(&1 in sub_domains())), "#{kind}: #{inspect(subs)}"

        assert Path.wildcard("#{@root}/application/#{kind}/*.ex") == [],
               "#{kind} must sit in a sub-domain folder"
      end
    end

    test "the adapters are grouped by sub-domain as well" do
      for sub <- sub_domains() do
        assert File.exists?("#{@root}/infrastructure/#{sub}/repository.ex")
        assert File.exists?("#{@root}/domain/#{sub}/repository.ex")
      end
    end

    # The one allowed mention of another aggregate is a reference to its id: `{:ref, Aggregate}`.
    test "sub-domains do not depend on each other: aggregates refer to each other by id" do
      for sub <- sub_domains(),
          other <- sub_domains() -- [sub],
          file <- Path.wildcard("#{@root}/domain/#{sub}/**/*.ex") ++ ["#{@root}/domain/#{sub}.ex"],
          source = file |> read() |> String.replace(~r/\{:ref,\s*TodoApp\.Domain\.\w+\}/, ""),
          source =~ ~r/TodoApp\.Domain\.#{Macro.camelize(other)}\b/ do
        flunk("#{file} mentions TodoApp.Domain.#{Macro.camelize(other)}")
      end
    end
  end

  test "the boundary compiler is enabled, so layer violations fail the build" do
    assert :boundary in Mix.Project.config()[:compilers]
  end
end
