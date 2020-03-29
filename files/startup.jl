import Pkg
let
    pkgs = ["Revise", "OhMyREPL", "Rebugger"]
    for pkg in pkgs
    if Base.find_package(pkg) === nothing
        Pkg.add(pkg)
    end
    end
end

try
  @eval using Revise
  # Turn on Revise's automatic-evaluation behavior
  Revise.async_steal_repl_backend()

  @eval using Rebugger
  # Activate Rebugger's key bindings
  atreplinit(Rebugger.repl_init)

  using OhMyREPL
  colorscheme!("Monokai24bit")

catch err
  @warn "Could not load startup packages."
end

ENV["JULIA_NUM_THREADS"] = 4
ENV["JULIA_CUDA_SILENT"] = 1

showall(x) = show(stdout, "text/plain", x)

# Update all packages, but do so in a worker process
import Distributed
let
    pkg_worker = Distributed.addprocs(1)[end]
    Distributed.remotecall(pkg_worker) do
        redirect_stdout() # silence everything, only on this worker
        redirect_stderr() # silence everything, only on this worker
        Pkg.update()

        # now remove this worker and say we are done
        remotecall(1) do
            eval(quote
                Distributed.rmprocs($(pkg_worker))
                printstyled("\n Pkg.update() complete \n"; color=:light_black)
            end)
        end
    end
end
