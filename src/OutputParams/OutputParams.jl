
#structure that contains outputting info
struct OutputParams{T <: Real, R <: Real, O}
    outputs::O         #tuple of entries defining names and quantities to be outputted
    output_freq::T     #output time 
    n_iter_out::R      #number of steps per output
    output_format::String     #specify output format [mat/jld]
    prefix::String     #file prefix
    output_path::String #folder in which to save
    dump_vel::Bool     #toggle on dumping the velocity after the final timestep
    zip_format::String     #specify whether or not to zip the output, and the format
    output_start::Bool  #flag to specify whether to output the initial state or not 
end

#output constructor
function OutputParams(; 
    outputs = (),
    output_freq = Inf, 
    output_format = "jld2",
    prefix = "outfile", 
    output_path = "./",
    dump_vel = false,
    zip_format = "none",
    output_start = false)

    #default the n_iter_out to -1 (this is updated in simulation once we know timestep from timestepping_params)
    n_iter_out = -1

    #check output_freq
    ((output_freq == Inf) || (output_freq > 0)) || throw(ArgumentError("output frequency must be positive or Inf"))

    #if you don't find folder, set it to the working directory
    if ~isdir(output_path)
        @warn string("Did not find output path ", output_path, ". Any outputs will go to the working directory", pwd())
        output_path = "./"
    end

    #append a "/" to folder if it doesn't have one
    endswith(output_path, "/") || (output_path = string(output_path, "/"))

    #throw an error if we don't get an output format we know
    ((output_format == "jld2") || (output_format == "mat")) || throw(ArgumentError("Output format must be `jld2` or `mat`"))

    #revert the zip format to none if we don't recognise format
    if ~(zip_format in ["none", "nc"])
        println("detected a zip format other than none or nc...
        WAVI currently only supports zipping to nc.
        Reverting to no zipping")
        zip_format = "none"
    end

    return OutputParams(outputs, output_freq, n_iter_out, output_format, prefix, output_path, dump_vel, zip_format, output_start)
end

include("output_writing.jl")
include("zipping_output.jl")