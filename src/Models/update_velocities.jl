"""
update_velocities!(model::AbstractModel)

Solve momentum equation to update the velocities, plus Picard iteration for non-linear rheology.

"""
function update_velocities!(model::AbstractModel{T,N}) where {T,N}
@unpack params,solver_params=model
@unpack gu,gv,wu,wv = model.fields
ni = gu.ni + gv.ni

x=get_start_guess(model)

resid=zeros(T,ni)
rel_resid=zero(T)
converged::Bool = false
i_picard::Int64 = 0
while !converged && (i_picard < solver_params.maxiter_picard)

    i_picard = i_picard + 1

    set_velocities!(model,x)
    update_shelf_strain_rate!(model)
    update_av_speed!(model)
    update_bed_speed!(model)
    update_β!(model)
    update_basal_drag!(model)
    inner_update_viscosity!(model)
    update_av_viscosity!(model)
    update_quadrature_falpha!(model)
    update_βeff!(model)
    update_βeff_on_uv_grids!(model)
    update_rheological_operators!(model)
    
    op=get_op(model)

    b=get_rhs(model)

    get_resid!(resid,x,op,b)

    rel_resid = norm(resid)/norm(b)
    converged = rel_resid < solver_params.tol_picard
    
    p=get_preconditioner(model,op)
    precondition!(x, p, b)
    
    correction_coarse = get_correction_coarse(p)
    set_correction_coarse!(model,correction_coarse)
end
set_velocities!(model,x)

return model
end


"""
    get_start_guess(model::AbstractModel)

 Return starting guess used to begin iterative solution of velocities.

"""
function get_start_guess(model::AbstractModel)
    @unpack gu,gv=model.fields
    @assert eltype(gu.u)==eltype(gv.v)
    x=[gu.samp_inner*gu.u[:];gv.samp_inner*gv.v[:]]
    return x
end


"""
    get_rhs(model::AbstractModel)

 Return right hand side vector of momentum equations.

"""
function get_rhs(model::AbstractModel{T,N}) where {T,N}
    @unpack gh,gu,gv,gc=model.fields
    @unpack params=model
    onesvec=ones(T,gh.nxh*gh.nyh)
    surf_elev_adjusted = gh.crop*(gh.s[:] .+ params.dt*gh.dsdh[:].*(gh.accumulation[:].-gh.basal_melt[:]))
    
    f1=[
        (params.density_ice*params.g*gu.h[gu.mask_inner]).*(gu.samp_inner*(-gu.∂xᵀ*surf_elev_adjusted))
        ;
        (params.density_ice*params.g*gv.h[gv.mask_inner]).*(gv.samp_inner*(-gv.∂yᵀ*surf_elev_adjusted))
       ]
    f2=[
        (0.5*params.density_ice*params.g*gu.h[gu.mask_inner].^2
        -0.5*params.density_ocean*params.g*(icedraft.(gu.s[gu.mask_inner],gu.h[gu.mask_inner],params.sea_level_wrt_geoid)).^2
        -params.density_ice*params.g*gu.h[gu.mask_inner].*gu.s[gu.mask_inner]).*gu.samp_inner*(-gu.∂xᵀ*(gh.crop*onesvec))
        ;
        (0.5*params.density_ice*params.g*gv.h[gv.mask_inner].^2
        -0.5*params.density_ocean*params.g*(icedraft.(gv.s[gv.mask_inner],gv.h[gv.mask_inner],params.sea_level_wrt_geoid)).^2
        -params.density_ice*params.g*gv.h[gv.mask_inner].*gv.s[gv.mask_inner]).*gv.samp_inner*(-gv.∂yᵀ*(gh.crop*onesvec))
        ]
    
    f3 = get_rhs_dirichlet(model)

    rhs=f1+f2+f3

    return rhs
end


"""
    set_velocities!(model::AbstractModel,x)

Set velocities to particular values. Input vector x represents stacked u and v components at valid grid points.
"""
function set_velocities!(model::AbstractModel,x)
    @unpack gh,gu,gv,gc=model.fields
    @views gu.u[gu.mask_inner] .= x[1:gu.ni]
    @views gv.v[gv.mask_inner] .= x[(gu.ni+1):(gu.ni+gv.ni)]
    return model
end

"""
    update_shelf_strain_rate!(model::AbstractModel)

Find the effective strain rate for 'ice shelf' parts of strain rate tensor, neglecting all vertical shear.
"""
function update_shelf_strain_rate!(model::AbstractModel)
    @unpack gh,gu,gv,gc=model.fields
    gh.shelf_strain_rate[:] .= sqrt.( (gh.crop*(gu.∂x*(gu.crop*gu.u[:]))).^2 .+
                                      (gh.crop*(gv.∂y*(gv.crop*gv.v[:]))).^2 .+
                                (gh.crop*(gu.∂x*(gu.crop*gu.u[:]))).*(gh.crop*(gv.∂y*(gv.crop*gv.v[:]))) .+
                       0.25*(gh.crop*(gc.cent*(gc.crop*( gu.∂y*(gu.crop*gu.u[:]) .+ gv.∂x*(gv.crop*gv.v[:]) )))).^2  )
    return model
end

"""
    update_av_speed!(model::AbstractModel)

Find the depth-averaged speed on the h-grid using components on u- and v- grids
"""
function update_av_speed!(model::AbstractModel)
    @unpack gh,gu,gv=model.fields
    gh.av_speed[:] .= sqrt.( (gh.crop*(gu.cent*(gu.crop*gu.u[:]))).^2 .+ (gh.crop*(gv.cent*(gv.crop*gv.v[:]))).^2 )
    return model
end

"""
    update_bed_speed!(model::AbstractModel)

Find the sliding speed at the bed on the h-grid using the average speed.
"""
function update_bed_speed!(model::AbstractModel)
    @unpack gh=model.fields
    gh.bed_speed .= gh.av_speed ./ (1.0 .+ gh.quad_f2 .* gh.β)
    return model
end

"""
    update_β!(model::AbstractModel)

Find the drag coefficient at the bed using the sliding law.
"""
function update_β!(model::AbstractModel)
    @unpack gh=model.fields
    @unpack params=model
    gh.β .= gh.weertman_c .* ( sqrt.(gh.bed_speed.^2 .+  params.weertman_reg_speed^2 ) ).^(1.0/params.weertman_m - 1.0)
    return model
end


"""
    update_basal_drag!(model::AbstractModel)

Find the shear stress at the bed.
"""
function update_basal_drag!(model::AbstractModel)
    @unpack gh=model.fields
    gh.τbed .= gh.β .* gh.bed_speed
    return model
end



"""
    inner_update_viscosity!(model::AbstractModel)

Inner update to iteratively refine viscosity on the 3d grid at all sigma levels.
"""
function inner_update_viscosity!(model::AbstractModel)
    @unpack gh,g3d=model.fields
    @unpack params,solver_params=model
    for k=1:g3d.nσs
        for j=1:g3d.nys
            for i=1:g3d.nxs
                if gh.mask[i,j]
                    for iter=1:solver_params.n_iter_viscosity
                        g3d.η[i,j,k] = 0.5 * g3d.glen_b[i,j,k] * (
                                                   sqrt(    gh.shelf_strain_rate[i,j]^2 +
                                                            0.25*(gh.τbed[i,j]*g3d.ζ[k]/g3d.η[i,j,k])^2 +
                                                            params.glen_reg_strain_rate^2   )
                                                                 )^(1.0/params.glen_n - 1.0)
                    end
                end
            end
        end
    end
    return model
end



"""
    update_av_viscosity!(model::AbstractModel)

Use quadrature to compute the depth averaged viscosity.
"""
function update_av_viscosity!(model::AbstractModel)
    @unpack gh,g3d=model.fields
    gh.ηav .= zero(gh.ηav)
    for k=1:g3d.nσs
       for j = 1:g3d.nys
          for i = 1:g3d.nxs
                gh.ηav[i,j] += g3d.quadrature_weights[k] * g3d.η[i,j,k]
          end
       end
    end
    return model
end


"""
    update_quadrature_falpha!(model::AbstractModel)

Use quadrature to compute falpha functions, used to relate average velocities, basal velocities, and surface velocities to one another
"""
function update_quadrature_falpha!(model::AbstractModel)
    @unpack gh,g3d=model.fields
    gh.quad_f1 .= zero(gh.quad_f1)
    gh.quad_f2 .= zero(gh.quad_f2)
    for k=1:g3d.nσs
       for j = 1:g3d.nys
          for i = 1:g3d.nxs
                gh.quad_f1[i,j] += g3d.quadrature_weights[k]*gh.h[i,j]*g3d.ζ[k]/g3d.η[i,j,k]
                gh.quad_f2[i,j] += g3d.quadrature_weights[k]*gh.h[i,j]*(g3d.ζ[k])^2/g3d.η[i,j,k]
          end
       end
    end
    return model
end

"""
    update_βeff!(model::AbstractModel)

Compute the effective drag coefficient.
"""
function update_βeff!(model::AbstractModel)
    @unpack gh=model.fields
    gh.βeff .= gh.β ./ (1.0 .+ gh.quad_f2 .* gh.β)
    return model
end



"""
    update_βeff_on_uv_grids!(model::AbstractModel)

Interpolate the effective drag coefficient onto u- and v-grids, accounting for grounded fraction.
"""
function update_βeff_on_uv_grids!(model::AbstractModel{T,N}) where {T,N}
    @unpack gh,gu,gv=model.fields
    @assert eltype(gh.grounded_fraction)==eltype(gh.βeff)

    onesvec=ones(T,gh.nxh*gh.nyh)
    gu.βeff[gu.mask].=(gu.samp*(gu.centᵀ*(gh.crop*gh.βeff[:])))./(gu.samp*(gu.centᵀ*(gh.crop*onesvec)))
    ipolgfu=zeros(T,gu.nxu,gu.nyu);
    ipolgfu[gu.mask].=(gu.samp*(gu.centᵀ*(gh.crop*gh.grounded_fraction[:])))./(gu.samp*(gu.centᵀ*(gh.crop*onesvec)))
    gu.βeff[ipolgfu .> zero(T)] .= gu.βeff[ipolgfu .> zero(T)].*gu.grounded_fraction[ipolgfu .> zero(T)]./
                                                        ipolgfu[ipolgfu .> zero(T)]

    gv.βeff[gv.mask].=(gv.samp*(gv.centᵀ*(gh.crop*gh.βeff[:])))./(gv.samp*(gv.centᵀ*(gh.crop*onesvec)))
    ipolgfv=zeros(T,gv.nxv,gv.nyv);
    ipolgfv[gv.mask].=(gv.samp*(gv.centᵀ*(gh.crop*gh.grounded_fraction[:])))./(gv.samp*(gv.centᵀ*(gh.crop*onesvec)))
    gv.βeff[ipolgfv .> zero(T)] .= gv.βeff[ipolgfv .> zero(T)].*gv.grounded_fraction[ipolgfv .> zero(T)]./
                                                 ipolgfv[ipolgfv .> zero(T)];

    return model
end


"""
    update_rheological_operators!(model::AbstractModel)

Precompute various diagonal matrices used in defining the momentum operator.
"""
function update_rheological_operators!(model::AbstractModel)
    @unpack gh,gu,gv=model.fields
    @unpack params=model
    gh.dneghηav[] .= gh.crop*Diagonal(-gh.h[:].*gh.ηav[:])*gh.crop
    gu.dnegβeff[] .= gu.crop*Diagonal(-gu.βeff[:])*gu.crop
    gv.dnegβeff[] .= gv.crop*Diagonal(-gv.βeff[:])*gv.crop
    gh.dimplicit[] .= gh.crop*Diagonal(-params.density_ice * params.g * params.dt * gh.dsdh[:])*gh.crop
    return model
end


"""
    get_op(model::AbstractModel{T,N}) where {T,N}

 Get operator, defined as a LinearMap type.

"""
function get_op(model::AbstractModel{T,N}) where {T,N}
    @unpack gu,gv=model.fields
    ni = gu.ni + gv.ni
    op_fun! = get_op_fun(model)
    op=LinearMap{T}(op_fun!,ni;issymmetric=true,ismutating=true,ishermitian=true,isposdef=true)
end


"""
    get_rhs_dirichlet(model::AbstractModel{T,N}) where {T,N}

    Extra term of right hand side to implement non-homogenous Dirichlet conditions   

"""
function get_rhs_dirichlet(model::AbstractModel{T,N}) where {T,N}
    @unpack gu,gv=model.fields

    rhs_dirichlet=zeros(T,gu.ni+gv.ni)
    
    uvfixed=[
    gu.u[:].*gu.u_isfixed[:]
    ;
    gv.v[:].*gv.v_isfixed[:]
    ]

    op_fun! = get_op_fun(model)
    op_fun!(rhs_dirichlet,uvfixed,vecSampled=false)
    
    @. rhs_dirichlet = - rhs_dirichlet
    
    return rhs_dirichlet
end