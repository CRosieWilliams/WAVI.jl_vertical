using WAVI, Test

@testset "Version Updates" begin
    @info "testing the current version of WAVI against previous version...."

    function version_update_test()
        #Grid and boundary conditions
        nx = 80
        ny = 10
        nσ = 4
        x0 = 0.0
        y0 = -40000.0
        dx = 8000.0
        dy = 8000.0
        h_mask=trues(nx,ny)
        u_iszero = falses(nx+1,ny); u_iszero[1,:].=true
        v_iszero=falses(nx,ny+1); v_iszero[:,1].=true; v_iszero[:,end].=true
        grid = Grid(nx = nx, 
                    ny = ny,   
                    nσ = nσ, 
                    x0 = x0, 
                    y0 = y0, 
                    dx = dx, 
                    dy = dy,
                    h_mask = h_mask, 
                    u_iszero = u_iszero, 
                    v_iszero = v_iszero)

        #Bed 
        bed = WAVI.mismip_plus_bed #function definition

        #solver parameters
        maxiter_picard = 1
        solver_params = SolverParams(maxiter_picard = maxiter_picard)

        #Physical parameters
        default_thickness = 100.0 #set the initial condition this way
        accumulation_rate = 0.3
        params = Params(default_thickness = default_thickness, 
                        accumulation_rate = accumulation_rate)

        #make the model
        model = Model(grid = grid,
                        bed_elevation = bed, 
                        params = params, 
                        solver_params = solver_params)

        #timestepping parameters
        niter0 = 0
        dt = 0.1
        end_time = 100.
        timestepping_params = TimesteppingParams(niter0 = niter0, 
                                                dt = dt, 
                                                end_time = end_time)

        #nb no output parameters

        simulation = Simulation(model = model, 
                            timestepping_params = timestepping_params)
                
        #perform the simulation
        run_simulation!(simulation)
        return simulation
    end

    simulation = version_update_test();
    example_output = load("./test/version_update_test_verification/MISMIP_100yr_output_8kmres_maxiter1_timesteppt1.jld2")
    @test all(isapprox.(simulation.model.fields.gh.h, example_output["h"], rtol = 1e-6)) 
    @test all(isapprox.(simulation.model.fields.gu.u, example_output["u"], rtol = 1e-4)) 
    @test all(isapprox.(simulation.model.fields.gv.v, example_output["v"], rtol = 1e-3)) 
    @test all(isapprox.(simulation.model.fields.gh.ηav, example_output["viscosity"], rtol = 1e-5)) 
    @test all(isapprox.(simulation.model.fields.gh.grounded_fraction, example_output["grounded_fraction"], rtol = 1e-5)) 
    @test all(isapprox.(simulation.model.fields.gh.bed_speed, example_output["bed_speed"], rtol = 1e-5)) 

    #only for julia version 1.5.1
    #@test simulation.model.fields.gh.h == example_output["h"]
    #@test simulation.model.fields.gu.u == example_output["u"]
    #@test simulation.model.fields.gv.v == example_output["v"]
    #@test simulation.model.fields.gh.ηav == example_output["viscosity"]
    #@test simulation.model.fields.gh.grounded_fraction == example_output["grounded_fraction"]
    #@test simulation.model.fields.gh.bed_speed == example_output["bed_speed"]
end


