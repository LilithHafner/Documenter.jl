# To fix all the output reference, run this file with
#
#    DOCUMENTER_FIXTESTS= julia doctests.jl
#
# If the inputs and outputs are giving you trouble, you can run the tests with
#
#    JULIA_DEBUG=DocTestsTests julia doctests.jl
#
# TODO: Combine the makedocs calls and stdout files. Also, allow running them one by one.
#
module DocTestsTests
using Test
using Documenter
using Documenter.Utilities.TextDiff: Diff, Words
import IOCapture

include("src/FooWorking.jl")
include("src/FooBroken.jl")
include("src/NoMeta.jl")

const builds_directory = joinpath(@__DIR__, "builds")
ispath(builds_directory) && rm(builds_directory, recursive=true)
mkpath(builds_directory)

function run_makedocs(f, mdfiles, modules=Module[]; kwargs...)
    dir = mktempdir(builds_directory)
    srcdir = joinpath(dir, "src"); mkpath(srcdir)

    for mdfile in mdfiles
        cp(joinpath(@__DIR__, "src", mdfile), joinpath(srcdir, mdfile))
    end
    # Create a dummy index.md file so that we wouldn't generate the "can't generated landing
    # page" warning.
    touch(joinpath(srcdir, "index.md"))

    c = IOCapture.capture(rethrow = InterruptException) do
        makedocs(
            sitename = " ",
            format = Documenter.HTML(edit_link = "master"),
            root = dir,
            modules = modules;
            kwargs...
        )
    end

    @debug """run_makedocs($mdfiles, modules=$modules) -> $(c.error ? "fail" : "success")
    ------------------------------------ output ------------------------------------
    $(c.output)
    --------------------------------------------------------------------------------
    """ c.value stacktrace(c.backtrace) dir

    write(joinpath(dir, "output"), c.output)
    write(joinpath(dir, "output.onormalize"), onormalize(c.output))
    open(joinpath(dir, "result"), "w") do io
        show(io, "text/plain", c.value)
        println(io, "-"^80)
        show(io, "text/plain", stacktrace(c.backtrace))
    end

    f(c.value, !c.error, c.backtrace, c.output)
end

function printoutput(result, success, backtrace, output)
    printstyled("="^80, color=:cyan); println()
    println(output)
    printstyled("-"^80, color=:cyan); println()
    println(repr(result))
    printstyled("-"^80, color=:cyan); println()
end

function onormalize(s)
    # Runs a bunch of regexes on captured documenter output strings to remove any machine /
    # platform / environment / time dependent parts, so that it would actually be possible
    # to compare Documenter output to previously generated reference outputs.

    # We need to make sure that, if we're running the tests on Windows, that we'll have consistent
    # line breaks. So we'll normalize CRLF to LF.
    if Sys.iswindows()
        s = replace(s, "\r\n" => "\n")
    end

    # Remove filesystem paths in doctests failures
    s = replace(s, r"(doctest failure in )(.*)$"m => s"\1{PATH}")
    s = replace(s, r"(@ Documenter.DocTests )(.*)$"m => s"\1{PATH}")

    # Remove stacktraces
    s = replace(s, r"(│\s+Stacktrace:)(\n(│\s+)\[[0-9]+\].*)(\n(│\s+)@.*)?+" => s"\1\\n\3{STACKTRACE}")

    return s
end

function is_same_as_file(output, filename)
    # Compares output to the contents of a reference file. Runs onormalize on both strings
    # before doing a character-by-character comparison.
    fixtests = haskey(ENV, "DOCUMENTER_FIXTESTS")
    success = if isfile(filename)
        reference = read(filename, String)
        if onormalize(reference) != onormalize(output)
            diff = Diff{Words}(onormalize(reference), onormalize(output))
            @error """Output does not agree with reference file
            ref: $(filename)
            ------------------------------------ output ------------------------------------
            $(output)
            ---------------------------------- reference  ----------------------------------
            $(reference)
            ------------------------------ onormalize(output) ------------------------------
            $(onormalize(output))
            ---------------------------- onormalize(reference)  ----------------------------
            $(onormalize(reference))
            """ diff
            false
        else
            true
        end
    else
        fixtests || error("Missing reference file: $(filename)")
        false
    end
    if fixtests && !success
        @info "Updating $(filename)"
        write(filename, output)
        success = true
    end
    return success
end

rfile(filename) = joinpath(@__DIR__, "stdouts", filename)

@testset "doctesting" begin
    # So, we have 4 doctests: 2 in a docstring, 2 in an .md file. One of either pair is
    # OK, other is broken. Here we first test all possible combinations of these doctest
    # with strict = true to make sure that the doctests are indeed failing.
    #
    # Some tests are broken due to https://github.com/JuliaDocs/Documenter.jl/issues/974
    run_makedocs(["working.md"]; strict=true) do result, success, backtrace, output
        @test success
        @test is_same_as_file(output, rfile("1.stdout"))
    end

    run_makedocs(["broken.md"]; strict=true) do result, success, backtrace, output
        @test !success
        @test is_same_as_file(output, rfile("2.stdout"))
    end

    run_makedocs(["working.md", "fooworking.md"]; modules=[FooWorking], strict=true) do result, success, backtrace, output
        @test success
        @test is_same_as_file(output, rfile("3.stdout"))
    end

    run_makedocs(["working.md", "foobroken.md"]; modules=[FooBroken], strict=true) do result, success, backtrace, output
        @test !success
        @test is_same_as_file(output, rfile("4.stdout"))
    end

    run_makedocs(["broken.md", "fooworking.md"]; modules=[FooWorking], strict=true) do result, success, backtrace, output
        @test !success
        @test is_same_as_file(output, rfile("5.stdout"))
    end

    for strict in (true, :doctest, [:doctest])
        run_makedocs(["broken.md", "foobroken.md"]; modules=[FooBroken], strict=strict) do result, success, backtrace, output
            @test !success
            @test is_same_as_file(output, rfile("6.stdout"))
        end
    end

    run_makedocs(["fooworking.md"]; modules=[FooWorking], strict=true) do result, success, backtrace, output
        @test success
        @test is_same_as_file(output, rfile("7.stdout"))
    end

    run_makedocs(["foobroken.md"]; modules=[FooBroken], strict=true) do result, success, backtrace, output
        @test !success
        @test is_same_as_file(output, rfile("8.stdout"))
    end

    # Here we try the default (strict = false) -- output should say that doctest failed, but
    # success should still be true.
    run_makedocs(["working.md"]) do result, success, backtrace, output
        @test success
        @test is_same_as_file(output, rfile("11.stdout"))
    end

    # Three options that do not strictly check doctests, including testing the default
    for strict_kw in ((; strict=false), NamedTuple(), (; strict=[:meta_block]))
        run_makedocs(["broken.md"]; strict_kw...) do result, success, backtrace, output
            @test success
            @test is_same_as_file(output, rfile("12.stdout"))
        end
    end

    # Tests for doctest = :only. The outout should reflect that the docs themselves do not
    # get built.
    run_makedocs(["working.md"]; modules=[FooWorking], doctest = :only) do result, success, backtrace, output
        @test success
        @test is_same_as_file(output, rfile("21.stdout"))
    end

    run_makedocs(["working.md"]; modules=[FooBroken], doctest = :only) do result, success, backtrace, output
        @test !success
        @test is_same_as_file(output, rfile("22.stdout"))
    end

    run_makedocs(["broken.md"]; modules=[FooWorking], doctest = :only) do result, success, backtrace, output
        @test !success
        @test is_same_as_file(output, rfile("23.stdout"))
    end

    run_makedocs(["broken.md"]; modules=[FooBroken], doctest = :only) do result, success, backtrace, output
        @test !success
        @test is_same_as_file(output, rfile("24.stdout"))
    end
    # strict gets ignored with doctest = :only
    run_makedocs(["broken.md"]; modules=[FooBroken], doctest = :only, strict=false) do result, success, backtrace, output
        @test !success
        @test is_same_as_file(output, rfile("25.stdout"))
    end

    # DocTestSetup in modules
    run_makedocs([]; modules=[NoMeta], doctest = :only) do result, success, backtrace, output
        @test !success
        @test is_same_as_file(output, rfile("31.stdout"))
    end
    # Now, let's use Documenter's APIs to add the necessary meta information
    DocMeta.setdocmeta!(NoMeta, :DocTestSetup, :(baz(x) = 2x))
    run_makedocs([]; modules=[NoMeta], doctest = :only) do result, success, backtrace, output
        @test success
        @test is_same_as_file(output, rfile("32.stdout"))
    end

    # Tests for special REPL softscope
    run_makedocs(["softscope.md"]) do result, success, backtrace, output
        @test success
        @test is_same_as_file(output, rfile("41.stdout"))
    end
end

using Documenter.DocTests: remove_common_backtrace
@testset "DocTest.remove_common_backtrace" begin
    @test remove_common_backtrace([], []) == []
    @test remove_common_backtrace([1], []) == [1]
    @test remove_common_backtrace([1,2], []) == [1,2]
    @test remove_common_backtrace([1,2,3], [1]) == [1,2,3]
    @test remove_common_backtrace([1,2,3], [2]) == [1,2,3]
    @test remove_common_backtrace([1,2,3], [3]) == [1,2]
    @test remove_common_backtrace([1,2,3], [2,3]) == [1]
    @test remove_common_backtrace([1,2,3], [1,3]) == [1,2]
    @test remove_common_backtrace([1,2,3], [1,2,3]) == []
    @test remove_common_backtrace([1,2,3], [0,1,2,3]) == []
end

end # module
