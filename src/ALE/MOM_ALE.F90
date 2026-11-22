! This file is part of MOM6, the Modular Ocean Model version 6.
! See the LICENSE file for licensing information.
! SPDX-License-Identifier: Apache-2.0

!> This module contains the main regridding routines.
!!
!! Regridding comprises two steps:
!! 1. Interpolation and creation of a new grid based on target interface
!!    densities (or any other criterion).
!! 2. Remapping of quantities between old grid and new grid.
!!
!! Original module written by Laurent White, 2008.06.09
module MOM_ALE

use MOM_debugging,        only : check_column_integrals
use MOM_diag_mediator,    only : register_diag_field, post_data, diag_ctrl
use MOM_diag_mediator,    only : time_type, diag_update_remap_grids, query_averaging_enabled
use MOM_domains,          only : create_group_pass, do_group_pass, group_pass_type
use MOM_error_handler,    only : MOM_error, FATAL, WARNING
use MOM_error_handler,    only : callTree_showQuery
use MOM_error_handler,    only : callTree_enter, callTree_leave, callTree_waypoint
use MOM_hybgen_unmix,     only : hybgen_unmix, init_hybgen_unmix, end_hybgen_unmix, hybgen_unmix_CS
use MOM_hybgen_regrid,    only : hybgen_regrid_CS
use MOM_file_parser,      only : get_param, param_file_type, log_param
use MOM_interface_heights,only : find_eta, calc_derived_thermo
use MOM_open_boundary,    only : ocean_OBC_type, OBC_DIRECTION_E, OBC_DIRECTION_W
use MOM_open_boundary,    only : OBC_DIRECTION_N, OBC_DIRECTION_S
use MOM_regridding,       only : initialize_regridding, regridding_main, end_regridding
use MOM_regridding,       only : uniformResolution
use MOM_regridding,       only : inflate_vanished_layers_old
use MOM_regridding,       only : regridding_preadjust_reqs, convective_adjustment
use MOM_regridding,       only : set_target_densities_from_GV, set_target_densities
use MOM_regridding,       only : regriddingCoordinateModeDoc, DEFAULT_COORDINATE_MODE
use MOM_regridding,       only : regriddingInterpSchemeDoc, regriddingDefaultInterpScheme
use MOM_regridding,       only : regriddingDefaultBoundaryExtrapolation
use MOM_regridding,       only : regriddingDefaultMinThickness
use MOM_regridding,       only : regridding_CS, set_regrid_params, write_regrid_file
use MOM_regridding,       only : getCoordinateInterfaces
use MOM_regridding,       only : getCoordinateUnits, getCoordinateShortName
use MOM_regridding,       only : getStaticThickness
use MOM_remapping,        only : initialize_remapping, end_remapping
use MOM_remapping,        only : remapping_core_h, remapping_core_w, remapping_core_h_columns
use MOM_remapping,        only : remappingSchemesDoc, remappingDefaultScheme
use MOM_remapping,        only : interpolate_column, reintegrate_column
use MOM_remapping,        only : remapping_CS, dzFromH1H2, remapping_set_param
use MOM_string_functions, only : uppercase, extractWord, extract_integer
use MOM_tracer_registry,  only : tracer_registry_type, tracer_type, MOM_tracer_chkinv
use MOM_unit_scaling,     only : unit_scale_type
use MOM_variables,        only : ocean_grid_type, thermo_var_ptrs
use MOM_verticalGrid,     only : get_thickness_units, verticalGrid_type

!use regrid_consts,       only : coordinateMode, DEFAULT_COORDINATE_MODE
use regrid_consts,        only : coordinateUnits, coordinateMode, state_dependent
use regrid_consts,        only : REGRIDDING_ZSTAR
use regrid_edge_values,   only : edge_values_implicit_h4
use PLM_functions,        only : PLM_reconstruction, PLM_boundary_extrapolation
use PLM_functions,        only : PLM_extrapolate_slope, PLM_monotonized_slope, PLM_slope_wa
use PPM_functions,        only : PPM_reconstruction, PPM_boundary_extrapolation
use Recon1d_PLM_WLS,      only : PLM_WLS

implicit none ; private
#include <MOM_memory.h>
#include "do_concurrent_compat.h"


!> ALE control structure
type, public :: ALE_CS ; private
  logical :: remap_uv_using_old_alg !< If true, uses the old "remapping via a delta z"
                                    !! method. If False, uses the new method that
                                    !! remaps between grids described by h.
  logical :: partial_cell_vel_remap !< If true, use partial cell thicknesses at velocity points
                                    !! that are masked out where they extend below the shallower
                                    !! of the neighboring bathymetry for remapping velocity.

  real :: regrid_time_scale !< The time-scale used in blending between the current (old) grid
                            !! and the target (new) grid [T ~> s]

  type(regridding_CS) :: regridCS !< Regridding parameters and work arrays
  type(remapping_CS)  :: remapCS  !< Remapping parameters and work arrays
  type(remapping_CS)  :: vel_remapCS  !< Remapping parameters for velocities and work arrays

  type(hybgen_unmix_CS), pointer :: hybgen_unmixCS => NULL() !< Parameters for hybgen remapping

  logical :: use_hybgen_unmix   !< If true, use the hybgen unmixing code before regridding
  logical :: do_conv_adj        !< If true, do convective adjustment before regridding

  integer :: nk             !< Used only for queries, not directly by this module
  real :: BBL_h_vel_mask    !< The thickness of a bottom boundary layer within which velocities in
                            !! thin layers are zeroed out after remapping, following practice with
                            !! Hybgen remapping, or a negative value to avoid such filtering
                            !! altogether, in [H ~> m or kg m-2].
  real :: h_vel_mask        !< A thickness at velocity points below which near-bottom layers are
                            !! zeroed out after remapping, following the practice with Hybgen
                            !! remapping, or a negative value to avoid such filtering altogether,
                            !! in [H ~> m or kg m-2].

  logical :: remap_after_initialization !< Indicates whether to regrid/remap after initializing the state.

  integer :: answer_date    !< The vintage of the expressions and order of arithmetic to use for
                            !! remapping. Values below 20190101 result in the use of older, less
                            !! accurate expressions that were in use at the end of 2018.  Higher
                            !! values result in the use of more robust and accurate forms of
                            !! mathematically equivalent expressions.

  logical :: conserve_ke    !< Apply a correction to the baroclinic velocity after remapping to
                            !! conserve KE.

  logical :: debug   !< If true, write verbose checksums for debugging purposes.
  logical :: show_call_tree !< For debugging

  integer :: niblock !< The i-direction block size used in the remapping calculations [nondim]
  integer :: njblock !< The j-direction block size used in the remapping calculations [nondim]

  ! for diagnostics
  type(diag_ctrl), pointer           :: diag                          !< structure to regulate output
  integer, dimension(:), allocatable :: id_tracer_remap_tendency      !< diagnostic id
  integer, dimension(:), allocatable :: id_Htracer_remap_tendency     !< diagnostic id
  integer, dimension(:), allocatable :: id_Htracer_remap_tendency_2d  !< diagnostic id
  logical, dimension(:), allocatable :: do_tendency_diag              !< flag for doing diagnostics
  integer                            :: id_dzRegrid = -1              !< diagnostic id

  ! diagnostic for fields prior to applying ALE remapping
  integer :: id_u_preale = -1 !< diagnostic id for zonal velocity before ALE.
  integer :: id_v_preale = -1 !< diagnostic id for meridional velocity before ALE.
  integer :: id_h_preale = -1 !< diagnostic id for layer thicknesses before ALE.
  integer :: id_T_preale = -1 !< diagnostic id for temperatures before ALE.
  integer :: id_S_preale = -1 !< diagnostic id for salinities before ALE.
  integer :: id_e_preale = -1 !< diagnostic id for interface heights before ALE.
  integer :: id_vert_remap_h = -1      !< diagnostic id for layer thicknesses used for remapping
  integer :: id_vert_remap_h_tendency = -1 !< diagnostic id for layer thickness tendency due to ALE
  integer :: id_remap_delta_integ_u2 = -1  !< Change in depth-integrated rho0*u**2/2
  integer :: id_remap_delta_integ_v2 = -1  !< Change in depth-integrated rho0*v**2/2

end type

! Publicly available functions
public ALE_init
public ALE_end
public ALE_regrid
public ALE_offline_inputs
public ALE_regrid_accelerated
public ALE_remap_scalar
public ALE_remap_tracers
public ALE_remap_velocities
public ALE_remap_set_h_vel, ALE_remap_set_h_vel_via_dz
public ALE_remap_interface_vals
public ALE_remap_vertex_vals
public ALE_PLM_edge_values
public TS_PLM_edge_values
public TS_PPM_edge_values
public TS_PLM_WLS_edge_values
public adjustGridForIntegrity
public ALE_initRegridding
public ALE_getCoordinate
public ALE_getCoordinateUnits
public ALE_writeCoordinateFile
public ALE_updateVerticalGridType
public ALE_initThicknessToCoord
public ALE_update_regrid_weights
public pre_ALE_diagnostics
public pre_ALE_adjustments
public ALE_remap_init_conds
public ALE_register_diags
public ALE_set_extrap_boundaries

! A note on unit descriptions in comments: MOM6 uses units that can be rescaled for dimensional
! consistency testing. These are noted in comments with units like Z, H, L, and T, along with
! their mks counterparts with notation like "a velocity [Z T-1 ~> m s-1]".  If the units
! vary with the Boussinesq approximation, the Boussinesq variant is given first.

!> The fixed declared extent of the column copies in remapped_vel_corrections in GPU builds, where
!! automatic arrays with a runtime size would be allocated on the device heap.  ALE_init checks
!! GV%ke against it on GPU builds.
integer, parameter :: fixed_col_extent = 128

#ifdef __NVCOMPILER_OPENMP_GPU
#define WSZK_(n)  fixed_col_extent
#else
#define WSZK_(n)  n
#endif

contains

!> This routine is typically called (from initialize_MOM in file MOM.F90)
!! before the main time integration loop to initialize the regridding stuff.
!! We read the MOM_input file to register the values of different
!! regridding/remapping parameters.
subroutine ALE_init( param_file, G, GV, US, max_depth, CS)
  type(param_file_type),   intent(in) :: param_file !< Parameter file
  type(ocean_grid_type),   intent(in) :: G          !< Grid structure
  type(verticalGrid_type), intent(in) :: GV         !< Ocean vertical grid structure
  type(unit_scale_type),   intent(in) :: US         !< A dimensional unit scaling type
  real,                    intent(in) :: max_depth  !< The maximum depth of the ocean [Z ~> m].
  type(ALE_CS),            pointer    :: CS         !< Module control structure

  ! Local variables
  character(len=40) :: mdl = "MOM_ALE" ! This module's name.
  character(len=80) :: string, vel_string ! Temporary strings
  real              :: filter_shallow_depth, filter_deep_depth ! Depth ranges of filtering [H ~> m or kg m-2]
  integer :: default_answer_date  ! The default setting for the various ANSWER_DATE flags.
  logical           :: check_reconstruction
  logical           :: check_remapping
  logical           :: force_bounds_in_subcell
  logical           :: local_logical
  logical           :: remap_boundary_extrap
  logical           :: init_boundary_extrap
  logical           :: om4_remap_via_sub_cells
  type(hybgen_regrid_CS), pointer :: hybgen_regridCS => NULL() ! Control structure for hybgen regridding
                                                         ! for sharing parameters.
  real :: h_neglect, h_neglect_edge ! small thicknesses [H ~> m or kg m-2]
#ifdef __NVCOMPILER_OPENMP_GPU
  integer, parameter :: default_niblock = 0, default_njblock = 0
  character(len=30) :: coord_mode   ! The vertical coordinate mode
  logical :: split, alt_split, remap_aux, offline, ice_shelf  ! Settings that GPU builds can not use with ALE
  integer :: nOBC_segments          ! The number of open boundary segments
#else
  integer, parameter :: default_niblock = 0, default_njblock = 1
#endif

  if (associated(CS)) then
    call MOM_error(WARNING, "ALE_init called with an associated "// &
                            "control structure.")
    return
  endif
  allocate(CS)

  CS%show_call_tree = callTree_showQuery()
  if (CS%show_call_tree) call callTree_enter("ALE_init(), MOM_ALE.F90")

  call get_param(param_file, mdl, "REMAP_UV_USING_OLD_ALG", CS%remap_uv_using_old_alg, &
                 "If true, uses the old remapping-via-a-delta-z method for "//&
                 "remapping u and v. If false, uses the new method that remaps "//&
                 "between grids described by an old and new thickness.", &
                 default=.false.)

  ! Initialize and configure regridding
  call ALE_initRegridding(G, GV, US, max_depth, param_file, mdl, CS%regridCS)
  call regridding_preadjust_reqs(CS%regridCS, CS%do_conv_adj, CS%use_hybgen_unmix, &
                                 hybgen_CS=hybgen_regridCS)

  ! Initialize and configure remapping that is orchestrated by ALE.
  call get_param(param_file, mdl, "REMAPPING_SCHEME", string, &
                 "This sets the reconstruction scheme used "//&
                 "for vertical remapping for all variables. "//&
                 "It can be one of the following schemes: \n"//&
                 trim(remappingSchemesDoc), default=remappingDefaultScheme)
  call get_param(param_file, mdl, "VELOCITY_REMAPPING_SCHEME", vel_string, &
                 "This sets the reconstruction scheme used for vertical remapping "//&
                 "of velocities. By default it is the same as REMAPPING_SCHEME. "//&
                 "It can be one of the following schemes: \n"//&
                 trim(remappingSchemesDoc), default=trim(string))
  call get_param(param_file, mdl, "FATAL_CHECK_RECONSTRUCTIONS", check_reconstruction, &
                 "If true, cell-by-cell reconstructions are checked for "//&
                 "consistency and if non-monotonicity or an inconsistency is "//&
                 "detected then a FATAL error is issued.", default=.false.)
  call get_param(param_file, mdl, "FATAL_CHECK_REMAPPING", check_remapping, &
                 "If true, the results of remapping are checked for "//&
                 "conservation and new extrema and if an inconsistency is "//&
                 "detected then a FATAL error is issued.", default=.false.)
  call get_param(param_file, mdl, "REMAP_BOUND_INTERMEDIATE_VALUES", force_bounds_in_subcell, &
                 "If true, the values on the intermediate grid used for remapping "//&
                 "are forced to be bounded, which might not be the case due to "//&
                 "round off.", default=.false.)
  call get_param(param_file, mdl, "REMAP_BOUNDARY_EXTRAP", remap_boundary_extrap, &
                 "If true, values at the interfaces of boundary cells are "//&
                 "extrapolated instead of piecewise constant", default=.false.)
  call get_param(param_file, mdl, "INIT_BOUNDARY_EXTRAP", init_boundary_extrap, &
                 "If true, values at the interfaces of boundary cells are "//&
                 "extrapolated instead of piecewise constant during initialization.  "//&
                 "Defaults to REMAP_BOUNDARY_EXTRAP.", default=remap_boundary_extrap)
  call get_param(param_file, mdl, "DEFAULT_ANSWER_DATE", default_answer_date, &
                 "This sets the default value for the various _ANSWER_DATE parameters.", &
                 default=99991231)
  call get_param(param_file, mdl, "REMAPPING_USE_OM4_SUBCELLS", om4_remap_via_sub_cells, &
                 "This selects the remapping algorithm used in OM4 that does not use "//&
                 "the full reconstruction for the top- and lower-most sub-layers, but instead "//&
                 "assumes they are always vanished (untrue) and so just uses their edge values. "//&
                 "We recommend setting this option to false.", default=.true.)
  call get_param(param_file, mdl, "REMAPPING_ANSWER_DATE", CS%answer_date, &
                 "The vintage of the expressions and order of arithmetic to use for remapping.  "//&
                 "Values below 20190101 result in the use of older, less accurate expressions "//&
                 "that were in use at the end of 2018.  Higher values result in the use of more "//&
                 "robust and accurate forms of mathematically equivalent expressions.", &
                 default=default_answer_date, do_not_log=.not.GV%Boussinesq)
  if (.not.GV%Boussinesq) CS%answer_date = max(CS%answer_date, 20230701)

  if (CS%answer_date >= 20190101) then
    h_neglect = GV%H_subroundoff ; h_neglect_edge = GV%H_subroundoff
  elseif (GV%Boussinesq) then
    h_neglect = GV%m_to_H * 1.0e-30 ; h_neglect_edge = GV%m_to_H * 1.0e-10
  else
    h_neglect = GV%kg_m2_to_H * 1.0e-30 ; h_neglect_edge = GV%kg_m2_to_H * 1.0e-10
  endif

  call initialize_remapping( CS%remapCS, string, nk=GV%ke, &
                             boundary_extrapolation=init_boundary_extrap, &
                             check_reconstruction=check_reconstruction, &
                             check_remapping=check_remapping, &
                             force_bounds_in_subcell=force_bounds_in_subcell, &
                             om4_remap_via_sub_cells=om4_remap_via_sub_cells, &
                             answer_date=CS%answer_date, &
                             h_neglect=h_neglect, h_neglect_edge=h_neglect_edge)
  call initialize_remapping( CS%vel_remapCS, vel_string, nk=GV%ke, &
                             boundary_extrapolation=init_boundary_extrap, &
                             check_reconstruction=check_reconstruction, &
                             check_remapping=check_remapping, &
                             force_bounds_in_subcell=force_bounds_in_subcell, &
                             om4_remap_via_sub_cells=om4_remap_via_sub_cells, &
                             answer_date=CS%answer_date, &
                             h_neglect=h_neglect, h_neglect_edge=h_neglect_edge)

  call get_param(param_file, mdl, "PARTIAL_CELL_VELOCITY_REMAP", CS%partial_cell_vel_remap, &
                 "If true, use partial cell thicknesses at velocity points that are masked out "//&
                 "where they extend below the shallower of the neighboring bathymetry for "//&
                 "remapping velocity.", default=.false.)

  call get_param(param_file, mdl, "REMAP_AFTER_INITIALIZATION", CS%remap_after_initialization, &
                 "If true, applies regridding and remapping immediately after "//&
                 "initialization so that the state is ALE consistent. This is a "//&
                 "legacy step and should not be needed if the initialization is "//&
                 "consistent with the coordinate mode.", default=.true.)

  call get_param(param_file, mdl, "REGRID_USE_DEPTH_BASED_TIME_FILTER", local_logical, &
                 "If true, always uses depth-based time filtering code that updates the "//&
                 "generated grid using REGRID_TIME_SCALE, REGRID_FILTER_SHALLOW_DEPTH, "//&
                 "REGRID_FILTER_DEEP_DEPTH parameters. Setting to True always uses "//&
                 "filtering but setting to False bypasses calculations when filter times = 0.", &
                 default=.true.)
  call set_regrid_params(CS%regridCS, use_depth_based_time_filter=local_logical)
  call get_param(param_file, mdl, "REGRID_TIME_SCALE", CS%regrid_time_scale, &
                 "The time-scale used in blending between the current (old) grid "//&
                 "and the target (new) grid. A short time-scale favors the target "//&
                 "grid (0. or anything less than DT_THERM) has no memory of the old "//&
                 "grid. A very long time-scale makes the model more Lagrangian.", &
                 units="s", default=0., scale=US%s_to_T)
  call get_param(param_file, mdl, "REGRID_FILTER_SHALLOW_DEPTH", filter_shallow_depth, &
                 "The depth above which no time-filtering is applied. Above this depth "//&
                 "final grid exactly matches the target (new) grid.", &
                 units="m", default=0., scale=GV%m_to_H)
  call get_param(param_file, mdl, "REGRID_FILTER_DEEP_DEPTH", filter_deep_depth, &
                 "The depth below which full time-filtering is applied with time-scale "//&
                 "REGRID_TIME_SCALE. Between depths REGRID_FILTER_SHALLOW_DEPTH and "//&
                 "REGRID_FILTER_DEEP_DEPTH the filter weights adopt a cubic profile.", &
                 units="m", default=0., scale=GV%m_to_H)
  call set_regrid_params(CS%regridCS, depth_of_time_filter_shallow=filter_shallow_depth, &
                         depth_of_time_filter_deep=filter_deep_depth)
  call get_param(param_file, mdl, "REGRID_USE_OLD_DIRECTION", local_logical, &
                 "If true, the regridding integrates upwards from the bottom for "//&
                 "interface positions, much as the main model does. If false "//&
                 "regridding integrates downward, consistent with the remapping code.", &
                 default=.true., do_not_log=.true.)
  call set_regrid_params(CS%regridCS, integrate_downward_for_e=.not.local_logical)

  call get_param(param_file, mdl, "REMAP_VEL_MASK_BBL_THICK", CS%BBL_h_vel_mask, &
                 "A thickness of a bottom boundary layer below which velocities in thin layers "//&
                 "are zeroed out after remapping, following practice with Hybgen remapping, "//&
                 "or a negative value to avoid such filtering altogether.", &
                 default=-0.001, units="m", scale=GV%m_to_H)
  call get_param(param_file, mdl, "REMAP_VEL_MASK_H_THIN", CS%h_vel_mask, &
                 "A thickness at velocity points below which near-bottom layers are zeroed out "//&
                 "after remapping, following practice with Hybgen remapping, "//&
                 "or a negative value to avoid such filtering altogether.", &
                 default=1.0e-6, units="m", scale=GV%m_to_H, do_not_log=(CS%BBL_h_vel_mask<=0.0))

  if (CS%use_hybgen_unmix) &
      call init_hybgen_unmix(CS%hybgen_unmixCS, GV, US, param_file, hybgen_regridCS)

  call get_param(param_file, mdl, "REMAP_VEL_CONSERVE_KE", CS%conserve_ke, &
                 "If true, a correction is applied to the baroclinic component of velocity "//&
                 "after remapping so that total KE is conserved. KE may not be conserved "//&
                 "when (CS%BBL_h_vel_mask > 0.0) .and. (CS%h_vel_mask > 0.0)", &
                 default=.false.)
  call get_param(param_file, "MOM", "DEBUG", CS%debug, &
                 "If true, write out verbose debugging data.", &
                 default=.false., debuggingParam=.true.)

  call get_param(param_file, mdl, "ALE_NIBLOCK", CS%niblock, &
                 "The i-direction block size used to hold the per-column working arrays in the "//&
                 "ALE regridding and remapping calculations.  The default 0 setting dynamically "//&
                 "uses the full width of the columns being worked on.", &
                 default=default_niblock, layoutParam=.true.)
  call get_param(param_file, mdl, "ALE_NJBLOCK", CS%njblock, &
                 "The j-direction block size used to hold the per-column working arrays in the "//&
                 "ALE regridding and remapping calculations.  The default 0 setting dynamically "//&
                 "uses the full width of the columns being worked on.", &
                 default=default_njblock, layoutParam=.true.)
  if (CS%niblock < 0) call MOM_error(FATAL, "ALE_init: ALE_NIBLOCK must be nonnegative; "//&
                                            "use 0 to select the full width.")
  if (CS%njblock < 0) call MOM_error(FATAL, "ALE_init: ALE_NJBLOCK must be nonnegative; "//&
                                            "use 0 to select the full width.")
  call set_regrid_params(CS%regridCS, niblock=CS%niblock, njblock=CS%njblock)

#ifdef __NVCOMPILER_OPENMP_GPU
  ! These are the features that the GPU port of the ALE regridding and remapping does not support.
  call get_param(param_file, mdl, "REGRIDDING_COORDINATE_MODE", coord_mode, &
                 default=DEFAULT_COORDINATE_MODE, do_not_log=.true.)
  call get_param(param_file, mdl, "SPLIT", split, default=.true., do_not_log=.true.)
  call get_param(param_file, mdl, "SPLIT_RK2B", alt_split, default=.false., do_not_log=.true.)
  call get_param(param_file, mdl, "REMAP_AUXILIARY_VARS", remap_aux, default=.false., do_not_log=.true.)
  call get_param(param_file, mdl, "OFFLINE_TRACER_MODE", offline, default=.false., do_not_log=.true.)
  call get_param(param_file, mdl, "ICE_SHELF", ice_shelf, default=.false., do_not_log=.true.)
  call get_param(param_file, mdl, "OBC_NUMBER_OF_SEGMENTS", nOBC_segments, default=0, do_not_log=.true.)
  if (GV%ke > fixed_col_extent) call MOM_error(FATAL, "ALE_init: GPU builds of the ALE require "//&
      "GV%ke <= fixed_col_extent; increase fixed_col_extent in MOM_ALE.F90, MOM_remapping.F90, "//&
      "MOM_regridding.F90, coord_zlike.F90, PCM_functions.F90 and PLM_functions.F90 (PLM_max_cells).")
  if (coordinateMode(coord_mode) /= REGRIDDING_ZSTAR) call MOM_error(FATAL, &
      "ALE_init: GPU builds only support REGRIDDING_COORDINATE_MODE = ZSTAR.")
  if (((uppercase(trim(string)) /= "PCM") .and. (uppercase(trim(string)) /= "PLM")) .or. &
      ((uppercase(trim(vel_string)) /= "PCM") .and. (uppercase(trim(vel_string)) /= "PLM"))) &
    call MOM_error(FATAL, "ALE_init: GPU builds only support PCM or PLM for REMAPPING_SCHEME "//&
                          "and VELOCITY_REMAPPING_SCHEME.")
  if (.not.om4_remap_via_sub_cells) call MOM_error(FATAL, &
      "ALE_init: GPU builds require REMAPPING_USE_OM4_SUBCELLS = True.")
  if (check_reconstruction .or. check_remapping) call MOM_error(FATAL, &
      "ALE_init: GPU builds do not support FATAL_CHECK_RECONSTRUCTIONS or FATAL_CHECK_REMAPPING.")
  if (.not.(GV%Boussinesq .or. GV%semi_Boussinesq)) call MOM_error(FATAL, &
      "ALE_init: GPU builds do not support ALE in non-Boussinesq mode.")
  if (nOBC_segments > 0) call MOM_error(FATAL, &
      "ALE_init: GPU builds do not support ALE with open boundary conditions.")
  if (ice_shelf) call MOM_error(FATAL, "ALE_init: GPU builds do not support ALE with ICE_SHELF.")
  if (split .and. alt_split .and. remap_aux) call MOM_error(FATAL, &
      "ALE_init: GPU builds do not support REMAP_AUXILIARY_VARS with SPLIT_RK2B.")
  if (offline) call MOM_error(FATAL, "ALE_init: GPU builds do not support ALE with OFFLINE_TRACER_MODE.")
#endif

  ! Keep a record of values for subsequent queries
  CS%nk = GV%ke

  if (CS%show_call_tree) call callTree_leave("ALE_init()")
end subroutine ALE_init

!> Sets the boundary extrapolation set for the remapping type.
subroutine ALE_set_extrap_boundaries( param_file, CS)
  type(param_file_type),   intent(in) :: param_file !< Parameter file
  type(ALE_CS),            pointer    :: CS         !< Module control structure

  logical :: remap_boundary_extrap
  call get_param(param_file, "MOM_ALE", "REMAP_BOUNDARY_EXTRAP", remap_boundary_extrap, &
                 "If true, values at the interfaces of boundary cells are "//&
                 "extrapolated instead of piecewise constant", default=.false.)
  call remapping_set_param(CS%remapCS, boundary_extrapolation=remap_boundary_extrap)
end subroutine ALE_set_extrap_boundaries

!> Sets the remapping algorithm to that of OM4
!!
!! The remapping aglorithm used in OM4 made poor assumptions about the reconstructions
!! in the top/bottom layers, namely that they were always vanished and could be
!! represented solely by their upper/lower edge value respectively.
!! Passing .false. here uses the full reconstruction of those top and bottom layers
!! and properly sample those layers.
subroutine ALE_set_OM4_remap_algorithm( CS, om4_remap_via_sub_cells )
  type(ALE_CS), pointer :: CS !< Module control structure
  logical, intent(in)   :: om4_remap_via_sub_cells !< If true, use OM4 remapping algorithm

  call remapping_set_param(CS%remapCS, om4_remap_via_sub_cells=om4_remap_via_sub_cells )

end subroutine ALE_set_OM4_remap_algorithm

!> Initialize diagnostics for the ALE module.
subroutine ALE_register_diags(Time, G, GV, US, diag, CS)
  type(time_type),target,     intent(in)  :: Time  !< Time structure
  type(ocean_grid_type),      intent(in)  :: G     !< Grid structure
  type(unit_scale_type),      intent(in)  :: US    !< A dimensional unit scaling type
  type(verticalGrid_type),    intent(in)  :: GV    !< Ocean vertical grid structure
  type(diag_ctrl), target,    intent(in)  :: diag  !< Diagnostics control structure
  type(ALE_CS), pointer                   :: CS    !< Module control structure

  ! Local variables
  character(len=48)  :: thickness_units

  CS%diag => diag
  thickness_units = get_thickness_units(GV)

  ! These diagnostics of the state variables before ALE are useful for
  ! debugging the ALE code.
  CS%id_u_preale = register_diag_field('ocean_model', 'u_preale', diag%axesCuL, Time, &
      'Zonal velocity before remapping', 'm s-1', conversion=US%L_T_to_m_s)
  CS%id_v_preale = register_diag_field('ocean_model', 'v_preale', diag%axesCvL, Time, &
      'Meridional velocity before remapping', 'm s-1', conversion=US%L_T_to_m_s)
  CS%id_h_preale = register_diag_field('ocean_model', 'h_preale', diag%axesTL, Time, &
      'Layer Thickness before remapping', thickness_units, conversion=GV%H_to_MKS, &
      v_extensive=.true.)
  CS%id_T_preale = register_diag_field('ocean_model', 'T_preale', diag%axesTL, Time, &
      'Temperature before remapping', 'degC', conversion=US%C_to_degC)
  CS%id_S_preale = register_diag_field('ocean_model', 'S_preale', diag%axesTL, Time, &
      'Salinity before remapping', 'PSU', conversion=US%S_to_ppt)
  CS%id_e_preale = register_diag_field('ocean_model', 'e_preale', diag%axesTi, Time, &
      'Interface Heights before remapping', 'm', conversion=US%Z_to_m)

  CS%id_dzRegrid = register_diag_field('ocean_model', 'dzRegrid', diag%axesTi, Time, &
      'Change in interface height due to ALE regridding', 'm', conversion=GV%H_to_m)
  CS%id_vert_remap_h = register_diag_field('ocean_model', 'vert_remap_h', diag%axestl, Time, &
      'layer thicknesses after ALE regridding and remapping', &
      thickness_units, conversion=GV%H_to_MKS, v_extensive=.true.)
  CS%id_vert_remap_h_tendency = register_diag_field('ocean_model', &
      'vert_remap_h_tendency', diag%axestl, Time, &
      'Layer thicknesses tendency due to ALE regridding and remapping', &
      trim(thickness_units)//" s-1", conversion=GV%H_to_MKS*US%s_to_T, v_extensive=.true.)
  CS%id_remap_delta_integ_u2 = register_diag_field('ocean_model', 'ale_u2', diag%axesCu1, Time, &
      'Rate of change in half rho0 times depth integral of squared zonal '//&
      'velocity by remapping. If REMAP_VEL_CONSERVE_KE is .true. then '//&
      'this measures the change before the KE-conserving correction is applied.', &
      'W m-2', conversion=US%RZ3_T3_to_W_m2*GV%H_to_RZ*US%L_to_Z**2)
  CS%id_remap_delta_integ_v2 = register_diag_field('ocean_model', 'ale_v2', diag%axesCv1, Time, &
      'Rate of change in half rho0 times depth integral of squared meridional '//&
      'velocity by remapping. If REMAP_VEL_CONSERVE_KE is .true. then '//&
      'this measures the change before the KE-conserving correction is applied.', &
      'W m-2', conversion=US%RZ3_T3_to_W_m2*GV%H_to_RZ*US%L_to_Z**2)

end subroutine ALE_register_diags

!> Crudely adjust (initial) grid for integrity.
!! This routine is typically called (from initialize_MOM in file MOM.F90)
!! before the main time integration loop to initialize the regridding stuff.
!! We read the MOM_input file to register the values of different
!! regridding/remapping parameters.
subroutine adjustGridForIntegrity( CS, G, GV, h )
  type(ALE_CS),                              intent(in)    :: CS  !< Regridding parameters and options
  type(ocean_grid_type),                     intent(in)    :: G   !< Ocean grid informations
  type(verticalGrid_type),                   intent(in)    :: GV  !< Ocean vertical grid structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(inout) :: h   !< Current 3D grid thickness that
                                                                  !! are to be adjusted [H ~> m or kg m-2]
  call inflate_vanished_layers_old( CS%regridCS, G, GV, h(:,:,:) )

end subroutine adjustGridForIntegrity


!> End of regridding (memory deallocation).
!! This routine is typically called (from MOM_end in file MOM.F90)
!! after the main time integration loop to deallocate the regridding stuff.
subroutine ALE_end(CS)
  type(ALE_CS), pointer :: CS  !< module control structure

  ! Deallocate memory used for the regridding
  call end_remapping( CS%remapCS )

  if (CS%use_hybgen_unmix) call end_hybgen_unmix( CS%hybgen_unmixCS )
  call end_regridding( CS%regridCS )

  deallocate(CS)

end subroutine ALE_end

!> Save any diagnostics of the state before ALE remapping.  These diagnostics are
!! mostly used for debugging.
subroutine pre_ALE_diagnostics(G, GV, US, h, u, v, tv, CS)
  type(ocean_grid_type),                      intent(in)    :: G   !< Ocean grid informations
  type(verticalGrid_type),                    intent(in)    :: GV  !< Ocean vertical grid structure
  type(unit_scale_type),                      intent(in)    :: US  !< A dimensional unit scaling type
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)),  intent(inout) :: h   !< Current 3D grid obtained after the
                                                                   !! last time step [H ~> m or kg m-2]
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV)), intent(inout) :: u   !< Zonal velocity field [L T-1 ~> m s-1]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV)), intent(inout) :: v   !< Meridional velocity field [L T-1 ~> m s-1]
  type(thermo_var_ptrs),                      intent(inout) :: tv  !< Thermodynamic variable structure
  type(ALE_CS),                               pointer       :: CS  !< Regridding parameters and options

  ! Local variables
  real :: eta_preale(SZI_(G),SZJ_(G),SZK_(GV)+1)  ! Interface heights before remapping [Z ~> m]

  if (CS%id_u_preale > 0) call post_data(CS%id_u_preale, u,    CS%diag)
  if (CS%id_v_preale > 0) call post_data(CS%id_v_preale, v,    CS%diag)
  if (CS%id_h_preale > 0) call post_data(CS%id_h_preale, h,    CS%diag)
  if (CS%id_T_preale > 0) call post_data(CS%id_T_preale, tv%T, CS%diag)
  if (CS%id_S_preale > 0) call post_data(CS%id_S_preale, tv%S, CS%diag)
  if (CS%id_e_preale > 0) then
    !$omp target update to(h)
    !$omp target enter data map(alloc: eta_preale)
    call find_eta(h, tv, G, GV, US, eta_preale, dZref=G%Z_ref)
    !$omp target exit data map(from: eta_preale)
    call post_data(CS%id_e_preale, eta_preale, CS%diag)
  endif

end subroutine pre_ALE_diagnostics


!> Potentially do some preparatory work, such as convective adjustment, to clean up the model
!! state before regridding.
subroutine pre_ALE_adjustments(G, GV, US, h, tv, Reg, CS, u, v)
  type(ocean_grid_type),                      intent(in)    :: G   !< Ocean grid informations
  type(verticalGrid_type),                    intent(in)    :: GV  !< Ocean vertical grid structure
  type(unit_scale_type),                      intent(in)    :: US  !< A dimensional unit scaling type
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)),  intent(inout) :: h   !< Current 3D grid obtained after the
                                                                   !! last time step [H ~> m or kg m-2]
  type(thermo_var_ptrs),                      intent(inout) :: tv  !< Thermodynamic variable structure
  type(tracer_registry_type),                 pointer       :: Reg !< Tracer registry structure
  type(ALE_CS),                               pointer       :: CS  !< Regridding parameters and options
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV)), &
                                    optional, intent(inout) :: u   !< Zonal velocity field [L T-1 ~> m s-1]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV)), &
                                    optional, intent(inout) :: v   !< Meridional velocity field [L T-1 ~> m s-1]

  integer :: ntr

  ! Do column-wise convective adjustment.
  ! Tracers and velocities should probably also undergo consistent adjustments.
  if (CS%do_conv_adj) call convective_adjustment(G, GV, h, tv)

  if (CS%use_hybgen_unmix) then
    ntr = 0 ; if (associated(Reg)) ntr = Reg%ntr
    call hybgen_unmix(G, GV, US, CS%hybgen_unmixCS, tv, Reg, ntr, h)
  endif

end subroutine pre_ALE_adjustments

!> Takes care of building a new grid. The creation of the new grid can be based on z coordinates,
!! target interface densities, sigma coordinates or any arbitrary coordinate system.
subroutine ALE_regrid( G, GV, US, h, h_new, dzRegrid, tv, CS, frac_shelf_h, PCM_cell)
  type(ocean_grid_type),                      intent(in)    :: G   !< Ocean grid informations
  type(verticalGrid_type),                    intent(in)    :: GV  !< Ocean vertical grid structure
  type(unit_scale_type),                      intent(in)    :: US  !< A dimensional unit scaling type
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)),  intent(in)    :: h   !< Layer thicknesses in 3D grid before
                                                                   !! regridding [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)),  intent(out)   :: h_new !< Layer thicknesses in 3D grid after
                                                                   !! regridding [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)+1), intent(out)  :: dzRegrid !< The change in grid interface positions
                                                                   !! due to regridding, in the same units as
                                                                   !! thicknesses [H ~> m or kg m-2]
  type(thermo_var_ptrs),                      intent(inout) :: tv  !< Thermodynamic variable structure
  type(ALE_CS),                               pointer       :: CS  !< Regridding parameters and options
  real, dimension(SZI_(G),SZJ_(G)), optional, intent(in)    :: frac_shelf_h !< Fractional ice shelf coverage [nondim]
  logical, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                                    optional, intent(out)   :: PCM_cell !< If true, use PCM remapping in a cell.

  ! Local variables
  logical :: showCallTree
  integer :: i, j, K, nz

  showCallTree = callTree_showQuery()

  if (showCallTree) call callTree_enter("ALE_regrid(), MOM_ALE.F90")

  ! Build the new grid and store it in h_new. The old grid is retained as h.
  ! Both are needed for the subsequent remapping of variables.
  ! h, h_new and dzRegrid are on the device, as they are in regridding_main.
  nz = GV%ke
  do concurrent (K=1:nz+1, j=G%jsd:G%jed, i=G%isd:G%ied)
    dzRegrid(i,j,K) = 0.0
  enddo
  call regridding_main( CS%remapCS, CS%regridCS, G, GV, US, h, tv, h_new, dzRegrid, &
                        frac_shelf_h=frac_shelf_h, PCM_cell=PCM_cell)

  if (CS%id_dzRegrid>0) then ; if (query_averaging_enabled(CS%diag)) then
    !$omp target update from(dzRegrid, h_new)
    call post_data(CS%id_dzRegrid, dzRegrid, CS%diag, alt_h=h_new)
  endif ; endif

  if (showCallTree) call callTree_leave("ALE_regrid()")

end subroutine ALE_regrid

!> Regrid/remap stored fields used for offline tracer integrations. These input fields are assumed to have
!! the same layer thicknesses at the end of the last offline interval (which should be a Zstar grid). This
!! routine builds a grid on the runtime specified vertical coordinate
subroutine ALE_offline_inputs(CS, G, GV, US, h, tv, Reg, uhtr, vhtr, Kd, debug, OBC)
  type(ALE_CS),                                 pointer       :: CS    !< Regridding parameters and options
  type(ocean_grid_type),                        intent(in   ) :: G     !< Ocean grid informations
  type(verticalGrid_type),                      intent(in   ) :: GV    !< Ocean vertical grid structure
  type(unit_scale_type),                        intent(in   ) :: US    !< A dimensional unit scaling type
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)),    intent(inout) :: h     !< Layer thicknesses [H ~> m or kg m-2]
  type(thermo_var_ptrs),                        intent(inout) :: tv    !< Thermodynamic variable structure
  type(tracer_registry_type),                   pointer       :: Reg   !< Tracer registry structure
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV)),   intent(inout) :: uhtr  !< Zonal mass fluxes [H L2 ~> m3 or kg]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV)),   intent(inout) :: vhtr  !< Meridional mass fluxes [H L2 ~> m3 or kg]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)+1),  intent(inout) :: Kd    !< Input diffusivities
                                                                       !! [H Z T-1 ~> m2 s-1 or kg m-1 s-1]
  logical,                                      intent(in   ) :: debug !< If true, then turn checksums
  type(ocean_OBC_type),                         pointer       :: OBC   !< Open boundary structure
  ! Local variables
  integer :: nk, i, j, k, isc, iec, jsc, jec
  real, dimension(SZI_(G), SZJ_(G), SZK_(GV))   :: h_new    ! Layer thicknesses after regridding [H ~> m or kg m-2]
  real, dimension(SZI_(G), SZJ_(G), SZK_(GV)+1) :: dzRegrid ! The change in grid interface positions [H ~> m or kg m-2]
  real, dimension(SZK_(GV)) :: h_src   ! Source grid thicknesses at velocity points [H ~> m or kg m-2]
  real, dimension(SZK_(GV)) :: h_dest  ! Destination grid thicknesses at velocity points [H ~> m or kg m-2]
  real, dimension(SZK_(GV)) :: temp_vec ! Transports on the destination grid [H L2 ~> m3 or kg]

  isc = G%isc ; iec = G%iec ; jsc = G%jsc ; jec = G%jec ; nk = GV%ke
  dzRegrid(:,:,:) = 0.0
  h_new(:,:,:) = 0.0

  if (debug) call MOM_tracer_chkinv("Before ALE_offline_inputs", G, GV, h, Reg%Tr, Reg%ntr)

  ! Build new grid from the Zstar state onto the requested vertical coordinate. The new grid is stored
  ! in h_new. The old grid is h. Both are needed for the subsequent remapping of variables. Convective
  ! adjustment right now is not used because it is unclear what to do with vanished layers
  call regridding_main( CS%remapCS, CS%regridCS, G, GV, US, h, tv, h_new, dzRegrid)
  if (CS%show_call_tree) call callTree_waypoint("new grid generated (ALE_offline_inputs)")

  ! Remap all variables from old grid h onto new grid h_new
  call ALE_remap_tracers(CS, G, GV, h, h_new, Reg, debug=CS%show_call_tree)
  if (allocated(tv%SpV_avg)) tv%valid_SpV_halo = -1   ! Record that SpV_avg is no longer valid.
  if (CS%show_call_tree) call callTree_waypoint("state remapped (ALE_inputs)")

  ! Reintegrate mass transports from Zstar to the offline vertical coordinate
  do j=jsc,jec ; do i=G%iscB,G%iecB
    if (G%mask2dCu(i,j)>0.) then
      h_src(:) = 0.5 * (h(i,j,:) + h(i+1,j,:))
      h_dest(:) = 0.5 * (h_new(i,j,:) + h_new(i+1,j,:))
      call reintegrate_column(nk, h_src, uhtr(I,j,:), nk, h_dest, temp_vec)
      uhtr(I,j,:) = temp_vec
    endif
  enddo ; enddo
  do j=G%jscB,G%jecB ; do i=isc,iec
    if (G%mask2dCv(i,j)>0.) then
      h_src(:) = 0.5 * (h(i,j,:) + h(i,j+1,:))
      h_dest(:) = 0.5 * (h_new(i,j,:) + h_new(i,j+1,:))
      call reintegrate_column(nk, h_src, vhtr(I,j,:), nk, h_dest, temp_vec)
      vhtr(I,j,:) = temp_vec
    endif
  enddo ; enddo

  do j=jsc,jec ; do i=isc,iec
    if (G%mask2dT(i,j)>0.) then
      if (check_column_integrals(nk, h_src, nk, h_dest)) then
        call MOM_error(FATAL, "ALE_offline_inputs: Kd interpolation columns do not match")
      endif
      call interpolate_column(nk, h(i,j,:), Kd(i,j,:), nk, h_new(i,j,:), Kd(i,j,:), .true.)
    endif
  enddo ; enddo

  call ALE_remap_scalar(CS%remapCS, G, GV, nk, h, tv%T, h_new, tv%T)
  call ALE_remap_scalar(CS%remapCS, G, GV, nk, h, tv%S, h_new, tv%S)

  if (debug) call MOM_tracer_chkinv("After ALE_offline_inputs", G, GV, h_new, Reg%Tr, Reg%ntr)

  ! Copy over the new layer thicknesses
  do k = 1,nk  ; do j = jsc-1,jec+1 ; do i = isc-1,iec+1
    h(i,j,k) = h_new(i,j,k)
  enddo ; enddo ; enddo

  if (allocated(tv%SpV_avg)) tv%valid_SpV_halo = -1   ! Record that SpV_avg is no longer valid.

  if (CS%show_call_tree) call callTree_leave("ALE_offline_inputs()")
end subroutine ALE_offline_inputs


!> For a state-based coordinate, accelerate the process of regridding by
!! repeatedly applying the grid calculation algorithm
subroutine ALE_regrid_accelerated(CS, G, GV, US, h, tv, n_itt, u, v, OBC, Reg, dt, &
                                  dzRegrid, initial)
  type(ALE_CS),            pointer       :: CS     !< ALE control structure
  type(ocean_grid_type),   intent(inout) :: G      !< Ocean grid
  type(verticalGrid_type), intent(in)    :: GV     !< Vertical grid
  type(unit_scale_type),   intent(in)    :: US     !< A dimensional unit scaling type
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: h      !< Original thicknesses [H ~> m or kg m-2]
  type(thermo_var_ptrs),   intent(inout) :: tv     !< Thermo vars (T/S/EOS)
  integer,                 intent(in)    :: n_itt  !< Number of times to regrid
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: u      !< Zonal velocity [L T-1 ~> m s-1]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV)), &
                           intent(inout) :: v      !< Meridional velocity [L T-1 ~> m s-1]
  type(ocean_OBC_type),    pointer       :: OBC    !< Open boundary structure
  type(tracer_registry_type), &
                 optional, pointer       :: Reg    !< Tracer registry to remap onto new grid
  real,          optional, intent(in)    :: dt     !< Model timestep to provide a timescale for regridding [T ~> s]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)+1), &
                 optional, intent(inout) :: dzRegrid !< Final change in interface positions [H ~> m or kg m-2]
  logical,       optional, intent(in)    :: initial !< Whether we're being called from an initialization
                                                    !! routine (and expect diagnostics to work)

  ! Local variables
  integer :: i, j, itt, nz
  type(thermo_var_ptrs) :: tv_local ! local/intermediate temp/salt
  type(group_pass_type) :: pass_T_S_h ! group pass if the coordinate has a stencil
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV))         :: h_loc  ! A working copy of layer thicknesses [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV))         :: h_orig ! The original layer thicknesses [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), target :: T      ! local temporary temperatures [C ~> degC]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), target :: S      ! local temporary salinities [S ~> ppt]
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV))        :: h_old_u ! Source grid thickness at zonal
                                                               ! velocity points [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV))        :: h_old_v ! Source grid thickness at meridional
                                                               ! velocity points [H ~> m or kg m-2]
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV))        :: h_new_u ! Destination grid thickness at zonal
                                                               ! velocity points [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV))        :: h_new_v ! Destination grid thickness at meridional
                                                               ! velocity points [H ~> m or kg m-2]

  ! we have to keep track of the total dzInterface if for some reason
  ! we're using the old remapping algorithm for u/v
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)+1) :: dzInterface ! Interface height changes within
                                                             ! an iteration [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)+1) :: dzIntTotal  ! Cumulative interface position changes [H ~> m or kg m-2]

  nz = GV%ke

  ! The regridding and the remapping of the tracers and velocities are done on the device, but
  ! the iterations remap temperature and salinity on the host.  h, u and v may already be mapped
  ! by an outer scope, so they are updated explicitly.
  !$omp target enter data map(alloc: h, u, v)
  !$omp target enter data map(alloc: h_loc, h_orig, dzInterface, dzIntTotal, h_old_u, h_old_v, h_new_u, h_new_v)
  !$omp target update to(u, v)

  ! initial total interface displacement due to successive regridding
  if (CS%remap_uv_using_old_alg) &
      dzIntTotal(:,:,:) = 0.

  call create_group_pass(pass_T_S_h, T, G%domain)
  call create_group_pass(pass_T_S_h, S, G%domain)
  call create_group_pass(pass_T_S_h, h_loc, G%domain)

  ! copy original temp/salt and set our local tv_pointers to them
  tv_local = tv
  T(:,:,:) = tv%T(:,:,:)
  S(:,:,:) = tv%S(:,:,:)
  tv_local%T => T
  tv_local%S => S

  ! get local copy of thickness and save original state for remapping
  h_loc(:,:,:) = h(:,:,:)
  h_orig(:,:,:) = h(:,:,:)

  ! Apply timescale to regridding (for e.g. filtered_grid_motion)
  if (present(dt)) &
      call ALE_update_regrid_weights(dt, CS)

  do itt = 1, n_itt

    call do_group_pass(pass_T_S_h, G%domain)

    ! generate new grid
    if (CS%do_conv_adj) call convective_adjustment(G, GV, h_loc, tv_local)

    ! Update the layer specific volumes if necessary
    if (allocated(tv_local%SpV_avg)) call calc_derived_thermo(tv_local, h, G, GV, US, halo=1)

    !$omp target update to(h_loc, h, dzInterface)
    call regridding_main(CS%remapCS, CS%regridCS, G, GV, US, h_loc, tv_local, h, dzInterface)
    !$omp target update from(h, dzInterface)
    if (CS%remap_uv_using_old_alg) &
        dzIntTotal(:,:,:) = dzIntTotal(:,:,:) + dzInterface(:,:,:)

    ! remap from original grid onto new grid
    do j = G%jsc-1,G%jec+1 ; do i = G%isc-1,G%iec+1
      call remapping_core_h(CS%remapCS, nz, h_orig(i,j,:), tv%S(i,j,:), nz, h(i,j,:), &
                            tv_local%S(i,j,:))
      call remapping_core_h(CS%remapCS, nz, h_orig(i,j,:), tv%T(i,j,:), nz, h(i,j,:), &
                            tv_local%T(i,j,:))
    enddo ; enddo

    ! starting grid for next iteration
    h_loc(:,:,:) = h(:,:,:)
  enddo

  ! remap all state variables (including those that weren't needed for regridding)
  !$omp target update to(h_orig, h, dzIntTotal)
  call ALE_remap_tracers(CS, G, GV, h_orig, h, Reg)

  call ALE_remap_set_h_vel(CS, G, GV, h_orig, h_old_u, h_old_v, OBC)
  if (CS%remap_uv_using_old_alg) then
    call ALE_remap_set_h_vel_via_dz(CS, G, GV, h, h_new_u, h_new_v, OBC, h_orig, dzIntTotal)
  else
    call ALE_remap_set_h_vel(CS, G, GV, h, h_new_u, h_new_v, OBC)
  endif

  call ALE_remap_velocities(CS, G, GV, h_old_u, h_old_v, h_new_u, h_new_v, u, v)
  !$omp target update from(u, v)
  !$omp target exit data map(delete: h_loc, h_orig, dzInterface, dzIntTotal, h_old_u, h_old_v, h_new_u, h_new_v)
  !$omp target exit data map(release: h, u, v)

  ! save total dzregrid for diags if needed?
  if (present(dzRegrid)) dzRegrid(:,:,:) = dzIntTotal(:,:,:)

  if (allocated(tv%SpV_avg)) tv%valid_SpV_halo = -1   ! Record that SpV_avg is no longer valid.

end subroutine ALE_regrid_accelerated

!> This routine takes care of remapping all tracer variables between the old and the
!! new grids. This routine is called during initialization of the model at time=0, to
!! remap initial conditions to the model grid.  It is also called during a
!! time step to update the state.  h_old and h_new must be current on the device, while
!! the tracers are host-owned and are current on the host on return.
subroutine ALE_remap_tracers(CS, G, GV, h_old, h_new, Reg, debug, dt, PCM_cell)
  type(ALE_CS),                              intent(in)    :: CS           !< ALE control structure
  type(ocean_grid_type),                     intent(in)    :: G            !< Ocean grid structure
  type(verticalGrid_type),                   intent(in)    :: GV           !< Ocean vertical grid structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_old        !< Thickness of source grid
                                                                           !! [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_new        !< Thickness of destination grid
                                                                           !! [H ~> m or kg m-2]
  type(tracer_registry_type),                pointer       :: Reg          !< Tracer registry structure
  logical,                         optional, intent(in)    :: debug  !< If true, show the call tree
  real,                            optional, intent(in)    :: dt     !< time step for diagnostics [T ~> s]
  logical, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                                   optional, intent(in)    :: PCM_cell !< Use PCM remapping in cells where true

  ! Local variables
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)) :: work_conc ! The rate of change of concentrations [Conc T-1 ~> Conc s-1]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)) :: work_cont ! The rate of change of cell-integrated tracer
                                                       ! content [Conc H T-1 ~> Conc m s-1 or Conc kg m-2 s-1] or
                                                       ! cell thickness [H T-1 ~> m s-1 or kg m-2 s-1]
  real, dimension(SZI_(G),SZJ_(G))          :: work_2d ! The rate of change of column-integrated tracer
                                                       ! content [Conc H T-1 ~> Conc m s-1 or Conc kg m-2 s-1]
  real :: Idt           ! The inverse of the timestep [T-1 ~> s-1]
  logical :: use_PCM    ! If true, PCM remapping is used in some cells
  logical :: do_conc, do_cont ! If true, find the tendencies of concentration and content
  logical :: show_call_tree
  integer :: i, j, k, m, nz, ntr

  show_call_tree = .false.
  if (present(debug)) show_call_tree = debug

  if (show_call_tree) call callTree_enter("ALE_remap_tracers(), MOM_ALE.F90")

  nz = GV%ke

  ntr = 0 ; if (associated(Reg)) ntr = Reg%ntr

  !$omp target enter data map(alloc: work_conc, work_cont, work_2d)

  Idt = 0.0
  if (present(dt)) then
    Idt = 1.0/dt
    do concurrent (k=1:nz, j=G%jsd:G%jed, i=G%isd:G%ied)
      work_conc(i,j,k) = 0.0
      work_cont(i,j,k) = 0.0
    enddo
  endif

  ! PCM_cell is only set to true by some coordinates.
  use_PCM = .false.
  if (present(PCM_cell)) use_PCM = any(PCM_cell(G%isc:G%iec,G%jsc:G%jec,:))

  ! Remap all registered tracers, including temperature and salinity.
  if (ntr>0) then
    if (show_call_tree) call callTree_waypoint("remapping tracers (ALE_remap_tracers)")
    do m=1,ntr ! For each tracer
      do_conc = .false. ; do_cont = .false.
      if (present(dt)) then
        do_conc = (Reg%Tr(m)%id_remap_conc > 0)
        do_cont = (Reg%Tr(m)%id_remap_cont > 0 .or. Reg%Tr(m)%id_remap_cont_2d > 0)
      endif
      if (use_PCM) then
        call remap_tracer_field(CS, G, GV, h_old, h_new, Reg%Tr(m)%t, Reg%Tr(m)%conc_underflow, &
                                do_conc, do_cont, Idt, work_conc, work_cont, PCM_cell)
      else
        call remap_tracer_field(CS, G, GV, h_old, h_new, Reg%Tr(m)%t, Reg%Tr(m)%conc_underflow, &
                                do_conc, do_cont, Idt, work_conc, work_cont)
      endif

      ! tendency diagnostics.
      if (present(dt)) then
        if (Reg%Tr(m)%id_remap_conc > 0) then
          !$omp target update from(work_conc)
          call post_data(Reg%Tr(m)%id_remap_conc, work_conc, CS%diag)
        endif
        if (Reg%Tr(m)%id_remap_cont > 0) then
          !$omp target update from(work_cont)
          call post_data(Reg%Tr(m)%id_remap_cont, work_cont, CS%diag)
        endif

        if (Reg%Tr(m)%id_remap_cont_2d > 0) then
          do concurrent (j=G%jsc:G%jec, i=G%isc:G%iec) DO_LOCALITY(local(k))
            work_2d(i,j) = 0.0
            do k = 1,nz
              work_2d(i,j) = work_2d(i,j) + work_cont(i,j,k)
            enddo
          enddo
          !$omp target update from(work_2d)
          call post_data(Reg%Tr(m)%id_remap_cont_2d, work_2d, CS%diag)
        endif
      endif
    enddo ! m=1,ntr

  endif  ! endif for ntr > 0


  if (CS%id_vert_remap_h > 0) then
    !$omp target update from(h_old)
    call post_data(CS%id_vert_remap_h, h_old, CS%diag)
  endif
  if ((CS%id_vert_remap_h_tendency > 0) .and. present(dt)) then
    do concurrent (k=1:nz, j=G%jsc:G%jec, i=G%isc:G%iec)
      work_cont(i,j,k) = (h_new(i,j,k) - h_old(i,j,k))*Idt
    enddo
    !$omp target update from(work_cont)
    call post_data(CS%id_vert_remap_h_tendency, work_cont, CS%diag)
  endif

  !$omp target exit data map(delete: work_conc, work_cont, work_2d)

  if (show_call_tree) call callTree_leave("ALE_remap_tracers(), MOM_ALE.F90")

end subroutine ALE_remap_tracers

!> Remaps one tracer concentration field between the old and the new grids in blocks of
!! columns, and finds the tendencies for the remapping diagnostics.  h_old, h_new, work_conc
!! and work_cont must be on the device, while tr is host-owned and is current on the host on return.
!! This is the body of the tracer loop in ALE_remap_tracers.  It is a separate routine so that each
!! tracer's concentrations (Reg%Tr(m)%t, a pointer) arrive as a non-pointer array that the kernels
!! here can use.
subroutine remap_tracer_field(CS, G, GV, h_old, h_new, tr, conc_underflow, do_conc, do_cont, Idt, &
                              work_conc, work_cont, PCM_cell)
  type(ALE_CS),                              intent(in)    :: CS     !< ALE control structure
  type(ocean_grid_type),                     intent(in)    :: G      !< Ocean grid structure
  type(verticalGrid_type),                   intent(in)    :: GV     !< Ocean vertical grid structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_old  !< Thickness of source grid
                                                                     !! [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_new  !< Thickness of destination grid
                                                                     !! [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(inout) :: tr     !< The tracer concentrations [Conc]
  real,                                      intent(in)    :: conc_underflow !< Concentrations smaller than
                                                                     !! this are set to 0 [Conc]
  logical,                                   intent(in)    :: do_conc !< If true, find work_conc
  logical,                                   intent(in)    :: do_cont !< If true, find work_cont
  real,                                      intent(in)    :: Idt    !< The inverse of the timestep [T-1 ~> s-1]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(inout) :: work_conc !< The rate of change of
                                                                     !! concentrations [Conc T-1 ~> Conc s-1]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(inout) :: work_cont !< The rate of change of
                                                                     !! cell-integrated tracer content
                                                                     !! [Conc H T-1 ~> Conc m s-1 or Conc kg m-2 s-1]
  logical, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                                   optional, intent(in)    :: PCM_cell !< Use PCM remapping in cells where true
  ! Local variables
  real, allocatable :: h1(:,:,:)        ! Block-sized source grid layer thicknesses [H ~> m or kg m-2]
  real, allocatable :: h2(:,:,:)        ! Block-sized target grid layer thicknesses [H ~> m or kg m-2]
  real, allocatable :: tr_src(:,:,:)    ! Block-sized tracer concentrations on the source grid [Conc]
  real, allocatable :: tr_column(:,:,:) ! Block-sized updated tracer concentrations [Conc]
  logical, allocatable :: PCM(:,:,:)    ! Block-sized copy of PCM_cell
  logical, allocatable :: active(:,:)   ! True for the ocean columns of a block
  integer :: i, j, k, nz
  integer :: nii, njj   ! The block sizes actually used, with 0 resolved to the full domain.
  integer :: isb, ieb   ! I-block bounds of the current block.
  integer :: jsb, jeb   ! J-block bounds of the current block.
  integer :: iie, jje   ! Valid block-local end bounds for blocked loops.
  integer :: ii, jj     ! Block-local 1-based i and j indices.

  nz = GV%ke
  nii = merge(G%iec-G%isc+1, CS%niblock, CS%niblock==0)
  njj = merge(G%jec-G%jsc+1, CS%njblock, CS%njblock==0)

  allocate(h1(nii,njj,nz), h2(nii,njj,nz), tr_src(nii,njj,nz), tr_column(nii,njj,nz), active(nii,njj))
  if (present(PCM_cell)) allocate(PCM(nii,njj,nz))
  !$omp target enter data map(alloc: h1, h2, tr_src, tr_column, active)
  ! The tracer may already be mapped by an outer scope, so it is updated explicitly.
  !$omp target enter data map(alloc: tr)
  !$omp target update to(tr)

  do jsb=G%jsc,G%jec,njj ; do isb=G%isc,G%iec,nii
    ieb = min(isb + nii - 1, G%iec)
    jeb = min(jsb + njj - 1, G%jec)
    iie = ieb - isb + 1 ; jje = jeb - jsb + 1

    ! Build the start and final grids.  Land columns are not remapped.
    do concurrent (jj=1:jje, ii=1:iie)
      active(ii,jj) = (G%mask2dT(isb+ii-1,jsb+jj-1) > 0.)
    enddo
    do concurrent (k=1:nz, jj=1:jje, ii=1:iie) DO_LOCALITY(local(i, j))
      i = isb + ii - 1 ; j = jsb + jj - 1
      if (G%mask2dT(i,j)>0.) then
        h1(ii,jj,k) = h_old(i,j,k)
        h2(ii,jj,k) = h_new(i,j,k)
        tr_src(ii,jj,k) = tr(i,j,k)
      else
        h1(ii,jj,k) = 0.0 ; h2(ii,jj,k) = 0.0 ; tr_src(ii,jj,k) = 0.0
      endif
    enddo

    if (present(PCM_cell)) then
      do k=1,nz ; do jj=1,jje ; do ii=1,iie
        PCM(ii,jj,k) = PCM_cell(isb+ii-1,jsb+jj-1,k)
      enddo ; enddo ; enddo
      call remapping_core_h_columns(CS%remapCS, nz, nz, nii, njj, iie, jje, active, h1, tr_src, h2, tr_column, &
                                    PCM_cell=PCM)
    else
      call remapping_core_h_columns(CS%remapCS, nz, nz, nii, njj, iie, jje, active, h1, tr_src, h2, tr_column)
    endif

    do concurrent (jj=1:jje, ii=1:iie, G%mask2dT(isb+ii-1,jsb+jj-1)>0.) DO_LOCALITY(local(i, j, k))
      i = isb + ii - 1 ; j = jsb + jj - 1

      ! Possibly underflow any very tiny tracer concentrations to 0.  Note that this is not conservative!
      if (conc_underflow > 0.0) then ; do k=1,nz
        if (abs(tr_column(ii,jj,k)) < conc_underflow) tr_column(ii,jj,k) = 0.0
      enddo ; endif

      ! Intermediate steps for tendency of tracer concentration and tracer content.
      if (do_conc) then
        do k=1,nz
          work_conc(i,j,k) = (tr_column(ii,jj,k) - tr(i,j,k)) * Idt
        enddo
      endif
      if (do_cont) then
        do k=1,nz
          work_cont(i,j,k) = (tr_column(ii,jj,k)*h2(ii,jj,k) - tr(i,j,k)*h1(ii,jj,k)) * Idt
        enddo
      endif

      ! update tracer concentration
      do k=1,nz
        tr(i,j,k) = tr_column(ii,jj,k)
      enddo
    enddo
  enddo ; enddo

  !$omp target update from(tr)
  !$omp target exit data map(release: tr)
  !$omp target exit data map(delete: h1, h2, tr_src, tr_column, active)
  deallocate(h1, h2, tr_src, tr_column, active)
  if (present(PCM_cell)) deallocate(PCM)

end subroutine remap_tracer_field

!> This routine sets the thicknesses at velocity points used for vertical remapping.
!! h_new, h_u and h_v must be on the device, and h_u and h_v are current there on return.
subroutine ALE_remap_set_h_vel(CS, G, GV, h_new, h_u, h_v, OBC, debug)
  type(ALE_CS),                              intent(in)    :: CS      !< ALE control structure
  type(ocean_grid_type),                     intent(in)    :: G       !< Ocean grid structure
  type(verticalGrid_type),                   intent(in)    :: GV      !< Ocean vertical grid structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_new   !< Thickness at tracer points of the
                                                                      !! grid being interpolated to velocity
                                                                      !! points [H ~> m or kg m-2]
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV)), &
                                             intent(inout) :: h_u     !< Grid thickness at zonal velocity
                                                                      !! points [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV)), &
                                             intent(inout) :: h_v     !< Grid thickness at meridional velocity
                                                                      !! points [H ~> m or kg m-2]
  type(ocean_OBC_type),                      pointer       :: OBC     !< Open boundary structure
  logical,                         optional, intent(in)    :: debug   !< If true, show the call tree

  ! Local variables
  logical :: show_call_tree
  integer :: i, j, k, nz

  show_call_tree = .false.
  if (present(debug)) show_call_tree = debug
  if (show_call_tree) call callTree_enter("ALE_remap_set_h_vel()")

  ! Build the u- and v-velocity grid thicknesses for remapping.
  nz = GV%ke

  do concurrent (k=1:nz, j=G%jsc:G%jec, I=G%IscB:G%IecB, G%mask2dCu(I,j)>0.)
    h_u(I,j,k) = 0.5*(h_new(i,j,k) + h_new(i+1,j,k))
  enddo
  do concurrent (k=1:nz, J=G%JscB:G%JecB, i=G%isc:G%iec, G%mask2dCv(i,J)>0.)
    h_v(i,J,k) = 0.5*(h_new(i,j,k) + h_new(i,j+1,k))
  enddo

  ! Mask out blocked portions of velocity cells.
  if (CS%partial_cell_vel_remap) call ALE_remap_set_h_vel_partial(CS, G, GV, h_new, h_u, h_v)

  ! Take open boundary conditions into account.
  if (associated(OBC)) then
#ifdef __NVCOMPILER_OPENMP_GPU
    call MOM_error(FATAL, "ALE_remap_set_h_vel: Open boundary conditions are not supported in GPU builds.")
#endif
    !$omp target update from(h_new, h_u, h_v)
    call ALE_remap_set_h_vel_OBC(G, GV, h_new, h_u, h_v, OBC)
    !$omp target update to(h_u, h_v)
  endif

  if (show_call_tree) call callTree_leave("ALE_remap_set_h_vel()")

end subroutine ALE_remap_set_h_vel

!> This routine sets the thicknesses at velocity points used for vertical remapping using a
!! combination of the old grid and interface movements.  h_new, h_old, dzInterface, h_u and h_v
!! must be on the device, and h_u and h_v are current there on return.
subroutine ALE_remap_set_h_vel_via_dz(CS, G, GV, h_new, h_u, h_v, OBC, h_old, dzInterface, debug)
  type(ALE_CS),                              intent(in)    :: CS           !< ALE control structure
  type(ocean_grid_type),                     intent(in)    :: G            !< Ocean grid structure
  type(verticalGrid_type),                   intent(in)    :: GV           !< Ocean vertical grid structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_new        !< Thickness at tracer points of the
                                                                           !! grid being interpolated to velocity
                                                                           !! points [H ~> m or kg m-2]
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV)), &
                                             intent(inout) :: h_u          !< Grid thickness at zonal velocity
                                                                           !! points [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV)), &
                                             intent(inout) :: h_v          !< Grid thickness at meridional velocity
                                                                           !! points [H ~> m or kg m-2]
  type(ocean_OBC_type),                      pointer       :: OBC          !< Open boundary structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                                             intent(in)    :: h_old        !< Thickness of source grid when generating
                                                                           !! the destination grid via the old
                                                                           !! algorithm [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)+1), &
                                             intent(in)    :: dzInterface  !< Change in interface position
                                                                           !! [H ~> m or kg m-2]
  logical,                         optional, intent(in)    :: debug        !< If true, show the call tree

  ! Local variables
  logical :: show_call_tree
  integer :: i, j, k, nz

  show_call_tree = .false.
  if (present(debug)) show_call_tree = debug
  if (show_call_tree) call callTree_enter("ALE_remap_set_h_vel()")

  ! Build the u- and v-velocity grid thicknesses for remapping using the old grid and interface movement.
  nz = GV%ke

  do concurrent (k=1:nz, j=G%jsc:G%jec, I=G%IscB:G%IecB, G%mask2dCu(I,j)>0.)
    h_u(I,j,k) = max( 0., 0.5*(h_old(i,j,k) + h_old(i+1,j,k)) + &
            0.5 * (( dzInterface(i,j,k) + dzInterface(i+1,j,k) ) - &
                   ( dzInterface(i,j,k+1) + dzInterface(i+1,j,k+1) )) )
  enddo

  do concurrent (k=1:nz, J=G%JscB:G%JecB, i=G%isc:G%iec, G%mask2dCv(i,J)>0.)
    h_v(i,J,k) = max( 0., 0.5*(h_old(i,j,k) + h_old(i,j+1,k)) + &
            0.5 * (( dzInterface(i,j,k) + dzInterface(i,j+1,k) ) - &
                   ( dzInterface(i,j,k+1) + dzInterface(i,j+1,k+1) )) )
  enddo

  ! Mask out blocked portions of velocity cells.
  if (CS%partial_cell_vel_remap) call ALE_remap_set_h_vel_partial(CS, G, GV, h_old, h_u, h_v)

  ! Take open boundary conditions into account.
  if (associated(OBC)) then
#ifdef __NVCOMPILER_OPENMP_GPU
    call MOM_error(FATAL, "ALE_remap_set_h_vel_via_dz: Open boundary conditions are not supported in GPU builds.")
#endif
    !$omp target update from(h_new, h_u, h_v)
    call ALE_remap_set_h_vel_OBC(G, GV, h_new, h_u, h_v, OBC)
    !$omp target update to(h_u, h_v)
  endif

  if (show_call_tree) call callTree_leave("ALE_remap_set_h_vel()")

end subroutine ALE_remap_set_h_vel_via_dz

!> Mask out the thicknesses at velocity points where they are below the minimum depth
!! at adjacent tracer points
subroutine ALE_remap_set_h_vel_partial(CS, G, GV, h_mask, h_u, h_v)
  type(ALE_CS),                              intent(in)    :: CS           !< ALE control structure
  type(ocean_grid_type),                     intent(in)    :: G            !< Ocean grid structure
  type(verticalGrid_type),                   intent(in)    :: GV           !< Ocean vertical grid structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_mask       !< Thickness at tracer points
                                                                           !! used to apply the partial
                                                                           !! cell masking [H ~> m or kg m-2]
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV)), &
                                             intent(inout) :: h_u          !< Grid thickness at zonal velocity
                                                                           !! points [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV)), &
                                             intent(inout) :: h_v          !< Grid thickness at meridional velocity
                                                                           !! points [H ~> m or kg m-2]
  ! Local variables
  real, dimension(SZI_(G),SZJ_(G)) :: h_tot  ! The vertically summed thicknesses [H ~> m or kg m-2]
  real :: h_mask_vel ! A depth below which the thicknesses at a velocity point are masked out [H ~> m or kg m-2]
  integer :: i, j, k, nz

  nz = GV%ke
  !$omp target enter data map(alloc: h_tot)

  do concurrent (j=G%jsc-1:G%jec+1, i=G%isc-1:G%iec+1) DO_LOCALITY(local(k))
    h_tot(i,j) = 0.0
    do k=1,nz
      h_tot(i,j) = h_tot(i,j) + h_mask(i,j,k)
    enddo
  enddo

  do concurrent (j=G%jsc:G%jec, I=G%IscB:G%IecB, G%mask2dCu(I,j)>0.) DO_LOCALITY(local(h_mask_vel))
    h_mask_vel = min(h_tot(i,j), h_tot(i+1,j))
    call apply_partial_cell_mask(G%IsdB, G%IedB, G%jsd, G%jed, nz, I, j, h_u, h_mask_vel)
  enddo

  do concurrent (J=G%JscB:G%JecB, i=G%isc:G%iec, G%mask2dCv(i,J)>0.) DO_LOCALITY(local(h_mask_vel))
    h_mask_vel = min(h_tot(i,j), h_tot(i,j+1))
    call apply_partial_cell_mask(G%isd, G%ied, G%JsdB, G%JedB, nz, i, J, h_v, h_mask_vel)
  enddo

  !$omp target exit data map(delete: h_tot)

end subroutine ALE_remap_set_h_vel_partial

!> Mask out the thicknesses in the column (i,j) of h1 after their running vertical sum exceeds h_mask.
!! The bounds of h1 are passed so that this works for thicknesses at either velocity point.
pure subroutine apply_partial_cell_mask(isd, ied, jsd, jed, nz, i, j, h1, h_mask)
  !$omp declare target
  integer, intent(in)    :: isd  !< The lower i-bound of h1
  integer, intent(in)    :: ied  !< The upper i-bound of h1
  integer, intent(in)    :: jsd  !< The lower j-bound of h1
  integer, intent(in)    :: jed  !< The upper j-bound of h1
  integer, intent(in)    :: nz   !< The number of layers in h1
  integer, value         :: i    !< The i-index of the column
  integer, value         :: j    !< The j-index of the column
  real, dimension(isd:ied,jsd:jed,nz), &
                 intent(inout) :: h1 !< Thicknesses to be masked out after their running vertical sum
                                     !! exceeds h_mask [H ~> m or kg m-2]
  real,          intent(in)    :: h_mask !< The depth after which the thicknesses in h1 are
                                     !! masked out [H ~> m or kg m-2]
  ! Local variables
  real :: h1_rsum  ! The running sum of h1 [H ~> m or kg m-2]
  integer :: k

  h1_rsum = 0.0
  do k=1,nz
    if (h1(i,j,k) > h_mask - h1_rsum) then
      ! This thickness is reduced because it extends below the shallower neighboring bathymetry.
      h1(i,j,k) = max(h_mask - h1_rsum, 0.0)
      h1_rsum = h_mask
    else
      h1_rsum = h1_rsum + h1(i,j,k)
    endif
  enddo
end subroutine apply_partial_cell_mask

! Reset thicknesses at velocity points on open boundary condition segments
subroutine ALE_remap_set_h_vel_OBC(G, GV, h_new, h_u, h_v, OBC)
  type(ocean_grid_type),                     intent(in)    :: G            !< Ocean grid structure
  type(verticalGrid_type),                   intent(in)    :: GV           !< Ocean vertical grid structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_new        !< Thickness at tracer points of the
                                                                           !! grid being interpolated to velocity
                                                                           !! points [H ~> m or kg m-2]
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV)), &
                                             intent(inout) :: h_u          !< Grid thickness at zonal velocity
                                                                           !! points [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV)), &
                                             intent(inout) :: h_v          !< Grid thickness at meridional velocity
                                                                           !! points [H ~> m or kg m-2]
  type(ocean_OBC_type),                      pointer       :: OBC          !< Open boundary structure

  ! Local variables
  integer :: i, j, k, nz, is_OBC, ie_OBC, js_OBC, je_OBC

  if (.not.associated(OBC)) return

  nz = GV%ke

  ! Take open boundary conditions into account.
  if (OBC%u_E_OBCs_on_PE) then
    js_OBC = max(G%jsc,  OBC%js_u_E_obc) ; je_OBC = min(G%jec,  OBC%je_u_E_obc)
    Is_OBC = max(G%IscB, OBC%Is_u_E_obc) ; Ie_OBC = min(G%IecB, OBC%Ie_u_E_obc)
    !$OMP parallel do default(shared)
    do j=js_OBC,je_OBC ; do I=Is_OBC,Ie_OBC ; if (OBC%segnum_u(I,j) > 0) then !  OBC_DIRECTION_E
      do k=1,nz ; h_u(I,j,k) = h_new(i,j,k) ; enddo
    endif ; enddo ; enddo
  endif
  if (OBC%u_W_OBCs_on_PE) then
    js_OBC = max(G%jsc,  OBC%js_u_W_obc) ; je_OBC = min(G%jec,  OBC%je_u_W_obc)
    Is_OBC = max(G%IscB, OBC%Is_u_W_obc) ; Ie_OBC = min(G%IecB, OBC%Ie_u_W_obc)
    !$OMP parallel do default(shared)
    do j=js_OBC,je_OBC ; do I=Is_OBC,Ie_OBC ; if (OBC%segnum_u(I,j) < 0) then !  OBC_DIRECTION_W
      do k=1,nz ; h_u(I,j,k) = h_new(i+1,j,k) ; enddo
    endif ; enddo ; enddo
  endif

  if (OBC%v_N_OBCs_on_PE) then
    Js_OBC = max(G%JscB, OBC%Js_v_N_obc) ; Je_OBC = min(G%JecB, OBC%Je_v_N_obc)
    is_OBC = max(G%isc,  OBC%is_v_N_obc) ; ie_OBC = min(G%iec,  OBC%ie_v_N_obc)
    !$OMP parallel do default(shared)
    do J=Js_OBC,Je_OBC ; do i=is_OBC,ie_OBC ; if (OBC%segnum_v(i,J) > 0) then !  OBC_DIRECTION_N
      do k=1,nz ; h_v(i,J,k) = h_new(i,j,k) ; enddo
    endif ; enddo ; enddo
  endif
  if (OBC%v_S_OBCs_on_PE) then
    Js_OBC = max(G%JscB, OBC%Js_v_S_obc) ; Je_OBC = min(G%JecB, OBC%Je_v_S_obc)
    is_OBC = max(G%isc,  OBC%is_v_S_obc) ; ie_OBC = min(G%iec,  OBC%ie_v_S_obc)
    !$OMP parallel do default(shared)
    do J=Js_OBC,Je_OBC ; do i=is_OBC,ie_OBC ; if (OBC%segnum_v(i,J) < 0) then !  OBC_DIRECTION_S
      do k=1,nz ; h_v(i,J,k) = h_new(i,j+1,k) ; enddo
    endif ; enddo ; enddo
  endif

end subroutine ALE_remap_set_h_vel_OBC

!> This routine remaps velocity components between the old and the new grids,
!! with thicknesses at velocity points taken to be arithmetic averages of tracer thicknesses.
!! This routine may be called during initialization of the model at time=0, to
!! remap initial conditions to the model grid.  It is also called during a
!! time step to update the state.  The thicknesses and velocities must be current on the
!! device, and u and v are current on the device (but not the host) on return.
subroutine ALE_remap_velocities(CS, G, GV, h_old_u, h_old_v, h_new_u, h_new_v, u, v, debug, &
                                dt, allow_preserve_variance)
  type(ALE_CS),                              intent(in)    :: CS        !< ALE control structure
  type(ocean_grid_type),                     intent(in)    :: G         !< Ocean grid structure
  type(verticalGrid_type),                   intent(in)    :: GV        !< Ocean vertical grid structure
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV)), &
                                             intent(in)    :: h_old_u   !< Source grid thickness at zonal
                                                                        !! velocity points [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV)), &
                                             intent(in)    :: h_old_v   !< Source grid thickness at meridional
                                                                        !! velocity points [H ~> m or kg m-2]
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV)), &
                                             intent(in)    :: h_new_u   !< Destination grid thickness at zonal
                                                                        !! velocity points [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV)), &
                                             intent(in)    :: h_new_v   !< Destination grid thickness at meridional
                                                                        !! velocity points [H ~> m or kg m-2]
  real, dimension(SZIB_(G),SZJ_(G),SZK_(GV)), &
                                             intent(inout) :: u         !< Zonal velocity [L T-1 ~> m s-1]
  real, dimension(SZI_(G),SZJB_(G),SZK_(GV)), &
                                             intent(inout) :: v         !< Meridional velocity [L T-1 ~> m s-1]
  logical,                         optional, intent(in)    :: debug     !< If true, show the call tree
  real,                            optional, intent(in)    :: dt        !< time step for diagnostics [T ~> s]
  logical,                         optional, intent(in)    :: allow_preserve_variance !< If true, enables ke-conserving
                                                                                      !! correction

  ! Local variables
  real, allocatable :: h1(:,:,:)    ! Block-sized source grid layer thicknesses [H ~> m or kg m-2]
  real, allocatable :: h2(:,:,:)    ! Block-sized target grid layer thicknesses [H ~> m or kg m-2]
  real, allocatable :: vel_src(:,:,:) ! Block-sized velocities on the source grid [L T-1 ~> m s-1]
  real, allocatable :: vel_tgt(:,:,:) ! Block-sized velocities on the target grid [L T-1 ~> m s-1]
  real, dimension(SZIB_(G),SZJ_(G)) :: du2h_tot  ! The rate of change of vertically integrated
                                                 ! 0.5 * rho0 *  u**2 [R Z L2 T-3 ~> W m-2]
  real, dimension(SZI_(G),SZJB_(G)) :: dv2h_tot  ! The rate of change of vertically integrated
                                                 ! 0.5 * rho0 *  v**2 [R Z L2 T-3 ~> W m-2]
  real :: u2h_tot, v2h_tot   ! The rate of change of vertically integrated 0.5 * rho0 * u**2 or v**2
                             ! in a column [R Z L2 T-3 ~> W m-2]
  real :: I_dt               ! 1 / dt [T-1 ~> s-1]
  real :: H_subroundoff      ! A negligible thickness [H ~> m or kg m-2]
  real :: BBL_h_vel_mask, h_vel_mask ! Copies of the CS thicknesses for masking velocities [H ~> m or kg m-2]
  logical :: variance_option ! Contains the value of allow_preserve_variance when present, else false
  logical :: conserve_ke     ! If true, apply the KE-conserving correction
  logical :: mask_vel        ! If true, zero out velocities in thin near-bottom layers
  logical :: do_u2, do_v2    ! If true, find the remapping change in the depth integrated u**2 or v**2
  logical :: show_call_tree
  integer :: i, j, k, nz
  integer :: nIIB, njj, IsbB, IebB, IIe, jsb, jeb, jje, II, jj  ! Block sizes, bounds and indices at u points
  integer :: nii, nJJB, isb, ieb, JsbB, JebB ! Block sizes and bounds at v points (iie is IIe and JJe is jje)
  logical, allocatable :: active(:,:) ! True for the ocean columns of a block

  show_call_tree = .false.
  if (present(debug)) show_call_tree = debug
  if (show_call_tree) call callTree_enter("ALE_remap_velocities()")

  ! Setup related to KE conservation
  variance_option = .false.
  if (present(allow_preserve_variance)) variance_option=allow_preserve_variance
  I_dt = 0.0 ; if (present(dt)) I_dt = 1.0 / dt

  do_u2 = (CS%id_remap_delta_integ_u2>0) ; do_v2 = (CS%id_remap_delta_integ_v2>0)
  conserve_ke = variance_option .and. CS%conserve_ke
  mask_vel = (CS%BBL_h_vel_mask > 0.0) .and. (CS%h_vel_mask > 0.0)
  BBL_h_vel_mask = CS%BBL_h_vel_mask ; h_vel_mask = CS%h_vel_mask
  H_subroundoff = GV%H_subroundoff

  if ((do_u2 .or. do_v2) .and. .not.present(dt))&
      call MOM_error(FATAL, "ALE KE diagnostics requires passing dt into ALE_remap_velocities")

  nz = GV%ke

  ! --- Remap u profiles from the source vertical grid onto the new target grid.

  nIIB = merge(G%IecB-G%IscB+1, CS%niblock, CS%niblock==0)
  njj = merge(G%jec-G%jsc+1, CS%njblock, CS%njblock==0)
  allocate(h1(nIIB,njj,nz), h2(nIIB,njj,nz), vel_src(nIIB,njj,nz), vel_tgt(nIIB,njj,nz), active(nIIB,njj))
  !$omp target enter data map(alloc: h1, h2, vel_src, vel_tgt, active, du2h_tot)

  if (do_u2) then
    do concurrent (j=G%jsd:G%jed, I=G%IsdB:G%IedB)
      du2h_tot(I,j) = 0.
    enddo
  endif

  do jsb=G%jsc,G%jec,njj ; do IsbB=G%IscB,G%IecB,nIIB
    IebB = min(IsbB + nIIB - 1, G%IecB)
    jeb = min(jsb + njj - 1, G%jec)
    IIe = IebB - IsbB + 1 ; jje = jeb - jsb + 1

    ! Make a block copy of the start and final grids and the source velocity.  Land columns are
    ! not remapped.
    do concurrent (jj=1:jje, II=1:IIe)
      active(II,jj) = (G%mask2dCu(IsbB+II-1,jsb+jj-1) > 0.)
    enddo
    do concurrent (k=1:nz, jj=1:jje, II=1:IIe) DO_LOCALITY(local(I, j))
      I = IsbB + II - 1 ; j = jsb + jj - 1
      if (G%mask2dCu(I,j)>0.) then
        h1(II,jj,k) = h_old_u(I,j,k)
        h2(II,jj,k) = h_new_u(I,j,k)
        vel_src(II,jj,k) = u(I,j,k)
      else
        h1(II,jj,k) = 0.0 ; h2(II,jj,k) = 0.0 ; vel_src(II,jj,k) = 0.0
      endif
    enddo

    call remapping_core_h_columns(CS%vel_remapCS, nz, nz, nIIB, njj, IIe, jje, active, h1, vel_src, h2, vel_tgt)

    do concurrent (jj=1:jje, II=1:IIe, G%mask2dCu(IsbB+II-1,jsb+jj-1)>0.) DO_LOCALITY(local(I, j, k, u2h_tot))
      I = IsbB + II - 1 ; j = jsb + jj - 1

      call remapped_vel_corrections(nz, nIIB, njj, II, jj, h1, h2, vel_src, vel_tgt, &
                                    conserve_ke, H_subroundoff, do_u2, I_dt, mask_vel, BBL_h_vel_mask, &
                                    h_vel_mask, u2h_tot)
      if (do_u2) du2h_tot(I,j) = u2h_tot

      ! Copy the column of new velocities back to the 3-d array
      do k=1,nz
        u(I,j,k) = vel_tgt(II,jj,k)
      enddo !k
    enddo
  enddo ; enddo

  if (do_u2) then
    !$omp target update from(du2h_tot)
    call post_data(CS%id_remap_delta_integ_u2, du2h_tot, CS%diag)
  endif

  !$omp target exit data map(delete: h1, h2, vel_src, vel_tgt, active, du2h_tot)
  deallocate(h1, h2, vel_src, vel_tgt, active)

  if (show_call_tree) call callTree_waypoint("u remapped (ALE_remap_velocities)")


  ! --- Remap v profiles from the source vertical grid onto the new target grid.

  nii = merge(G%iec-G%isc+1, CS%niblock, CS%niblock==0)
  nJJB = merge(G%JecB-G%JscB+1, CS%njblock, CS%njblock==0)
  allocate(h1(nii,nJJB,nz), h2(nii,nJJB,nz), vel_src(nii,nJJB,nz), vel_tgt(nii,nJJB,nz), active(nii,nJJB))
  !$omp target enter data map(alloc: h1, h2, vel_src, vel_tgt, active, dv2h_tot)

  if (do_v2) then
    do concurrent (J=G%JsdB:G%JedB, i=G%isd:G%ied)
      dv2h_tot(i,J) = 0.
    enddo
  endif

  do JsbB=G%JscB,G%JecB,nJJB ; do isb=G%isc,G%iec,nii
    ieb = min(isb + nii - 1, G%iec)
    JebB = min(JsbB + nJJB - 1, G%JecB)
    iie = ieb - isb + 1 ; JJe = JebB - JsbB + 1

    do concurrent (JJ=1:JJe, ii=1:iie)
      active(ii,JJ) = (G%mask2dCv(isb+ii-1,JsbB+JJ-1) > 0.)
    enddo
    do concurrent (k=1:nz, JJ=1:JJe, ii=1:iie) DO_LOCALITY(local(i, J))
      i = isb + ii - 1 ; J = JsbB + JJ - 1
      if (G%mask2dCv(i,J)>0.) then
        h1(ii,JJ,k) = h_old_v(i,J,k)
        h2(ii,JJ,k) = h_new_v(i,J,k)
        vel_src(ii,JJ,k) = v(i,J,k)
      else
        h1(ii,JJ,k) = 0.0 ; h2(ii,JJ,k) = 0.0 ; vel_src(ii,JJ,k) = 0.0
      endif
    enddo

    call remapping_core_h_columns(CS%vel_remapCS, nz, nz, nii, nJJB, iie, JJe, active, h1, vel_src, h2, vel_tgt)

    do concurrent (JJ=1:JJe, ii=1:iie, G%mask2dCv(isb+ii-1,JsbB+JJ-1)>0.) DO_LOCALITY(local(i, J, k, v2h_tot))
      i = isb + ii - 1 ; J = JsbB + JJ - 1

      call remapped_vel_corrections(nz, nii, nJJB, ii, JJ, h1, h2, vel_src, vel_tgt, &
                                    conserve_ke, H_subroundoff, do_v2, I_dt, mask_vel, BBL_h_vel_mask, &
                                    h_vel_mask, v2h_tot)
      if (do_v2) dv2h_tot(i,J) = v2h_tot

      ! Copy the column of new velocities back to the 3-d array
      do k=1,nz
        v(i,J,k) = vel_tgt(ii,JJ,k)
      enddo !k
    enddo
  enddo ; enddo

  if (do_v2) then
    !$omp target update from(dv2h_tot)
    call post_data(CS%id_remap_delta_integ_v2, dv2h_tot, CS%diag)
  endif

  !$omp target exit data map(delete: h1, h2, vel_src, vel_tgt, active, dv2h_tot)
  deallocate(h1, h2, vel_src, vel_tgt, active)

  if (show_call_tree) call callTree_waypoint("v remapped (ALE_remap_velocities)")
  if (show_call_tree) call callTree_leave("ALE_remap_velocities()")

end subroutine ALE_remap_velocities

!> Interpolate to find an updated array of values at interfaces after remapping.
subroutine ALE_remap_interface_vals(CS, G, GV, h_old, h_new, int_val)
  type(ALE_CS),                              intent(in)    :: CS       !< ALE control structure
  type(ocean_grid_type),                     intent(in)    :: G        !< Ocean grid structure
  type(verticalGrid_type),                   intent(in)    :: GV       !< Ocean vertical grid structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_old    !< Thickness of source grid
                                                                       !! [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_new    !< Thickness of destination grid
                                                                       !! [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)+1), &
                                             intent(inout) :: int_val  !< The interface values to interpolate [A]

  real :: val_src(GV%ke+1)  ! A column of interface values on the source grid [A]
  real :: val_tgt(GV%ke+1)  ! A column of interface values on the target grid [A]
  real :: h_src(GV%ke)      ! A column of source grid layer thicknesses [H ~> m or kg m-2]
  real :: h_tgt(GV%ke)      ! A column of target grid layer thicknesses [H ~> m or kg m-2]
  integer :: i, j, k, nz

  nz = GV%ke

  do j=G%jsc,G%jec ; do i=G%isc,G%iec ; if (G%mask2dT(i,j)>0.) then
    do k=1,nz
      h_src(k) = h_old(i,j,k)
      h_tgt(k) = h_new(i,j,k)
    enddo

    do K=1,nz+1
      val_src(K) = int_val(i,j,K)
    enddo

    call interpolate_column(nz, h_src, val_src, nz, h_tgt, val_tgt, .false.)

    do K=1,nz+1
      int_val(i,j,K) = val_tgt(K)
    enddo
  endif ; enddo ; enddo

end subroutine ALE_remap_interface_vals

!> Interpolate to find an updated array of values at vertices of tracer cells after remapping.
subroutine ALE_remap_vertex_vals(CS, G, GV, h_old, h_new, vert_val)
  type(ALE_CS),                              intent(in)    :: CS       !< ALE control structure
  type(ocean_grid_type),                     intent(in)    :: G        !< Ocean grid structure
  type(verticalGrid_type),                   intent(in)    :: GV       !< Ocean vertical grid structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_old    !< Thickness of source grid
                                                                       !! [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(in)    :: h_new    !< Thickness of destination grid
                                                                       !! [H ~> m or kg m-2]
  real, dimension(SZIB_(G),SZJB_(G),SZK_(GV)+1), &
                                             intent(inout) :: vert_val  !< The interface values to interpolate [A]

  real :: val_src(GV%ke+1)  ! A column of interface values on the source grid [A]
  real :: val_tgt(GV%ke+1)  ! A column of interface values on the target grid [A]
  real :: h_src(GV%ke)      ! A column of source grid layer thicknesses [H ~> m or kg m-2]
  real :: h_tgt(GV%ke)      ! A column of target grid layer thicknesses [H ~> m or kg m-2]
  real :: I_mask_sum        ! The inverse of the tracer point masks surrounding a corner [nondim]
  integer :: i, j, k, nz

  nz = GV%ke

  do J=G%JscB,G%JecB ; do I=G%IscB,G%IecB
    if ((G%mask2dT(i,j) + G%mask2dT(i+1,j+1)) + (G%mask2dT(i+1,j) + G%mask2dT(i,j+1)) > 0.0 ) then
      I_mask_sum = 1.0 / ((G%mask2dT(i,j) + G%mask2dT(i+1,j+1)) + &
                          (G%mask2dT(i+1,j) + G%mask2dT(i,j+1)))

    do k=1,nz
      h_src(k) = ((G%mask2dT(i,j) * h_old(i,j,k) + G%mask2dT(i+1,j+1) * h_old(i+1,j+1,k)) + &
          (G%mask2dT(i+1,j) * h_old(i+1,j,k) + G%mask2dT(i,j+1) * h_old(i,j+1,k)) ) * I_mask_sum
      h_tgt(k) = ((G%mask2dT(i,j) * h_new(i,j,k) + G%mask2dT(i+1,j+1) * h_new(i+1,j+1,k)) + &
          (G%mask2dT(i+1,j) * h_new(i+1,j,k) + G%mask2dT(i,j+1) * h_new(i,j+1,k)) ) * I_mask_sum
    enddo

    do K=1,nz+1
      val_src(K) = vert_val(I,J,K)
    enddo

    call interpolate_column(nz, h_src, val_src, nz, h_tgt, val_tgt, .false.)

    do K=1,nz+1
      vert_val(I,J,K) = val_tgt(K)
    enddo
  endif ; enddo ; enddo

end subroutine ALE_remap_vertex_vals



!> Applies the corrections to the column (ii,jj) of the block of remapped velocities in
!! ALE_remap_velocities: the KE-conserving correction to the baroclinic velocity, the change in the
!! depth integral of the squared velocity for the diagnostics, and the zeroing of velocities in thin
!! near-bottom layers.  The work is done on contiguous copies of the column.
pure subroutine remapped_vel_corrections(nz, nib, njb, ii, jj, h1_blk, h2_blk, vel_src_blk, vel_tgt_blk, &
                                         conserve_ke, H_subroundoff, do_vel2, I_dt, mask_vel, BBL_h_vel_mask, &
                                         h_vel_mask, dvel2h_tot)
  !$omp declare target
  integer, intent(in)    :: nz          !< The number of layers in each column
  integer, intent(in)    :: nib         !< The i-size of the block arrays
  integer, intent(in)    :: njb         !< The j-size of the block arrays
  integer, value         :: ii          !< The block-local i index of the column
  integer, value         :: jj          !< The block-local j index of the column
  real,    intent(in)    :: h1_blk(nib,njb,nz)  !< Source grid layer thicknesses [H ~> m or kg m-2]
  real,    intent(in)    :: h2_blk(nib,njb,nz)  !< Target grid layer thicknesses [H ~> m or kg m-2]
  real,    intent(in)    :: vel_src_blk(nib,njb,nz) !< Velocities on the source grid [L T-1 ~> m s-1]
  real,    intent(inout) :: vel_tgt_blk(nib,njb,nz) !< Velocities remapped to the target grid [L T-1 ~> m s-1]
  logical, intent(in)    :: conserve_ke !< If true, apply the KE-conserving correction
  real,    intent(in)    :: H_subroundoff !< A negligible thickness [H ~> m or kg m-2]
  logical, intent(in)    :: do_vel2     !< If true, find dvel2h_tot
  real,    intent(in)    :: I_dt        !< 1 / dt [T-1 ~> s-1]
  logical, intent(in)    :: mask_vel    !< If true, zero out velocities in thin near-bottom layers
  real,    intent(in)    :: BBL_h_vel_mask !< The thickness of a bottom boundary layer within which
                                        !! velocities in thin layers are zeroed out [H ~> m or kg m-2]
  real,    intent(in)    :: h_vel_mask  !< A thickness below which near-bottom layers are zeroed out [H ~> m or kg m-2]
  real,    intent(out)   :: dvel2h_tot  !< The rate of change of vertically integrated
                                        !! 0.5 * rho0 * vel**2 [R Z L2 T-3 ~> W m-2], set if do_vel2 is true
  ! Local variables
  real :: rescale_coef  ! Factor that scales the baroclinic velocity to conserve ke [nondim]
  real :: vel_bt        ! Depth-averaged velocity [L T-1 ~> m s-1]
  real :: h2_tot        ! The total target grid thickness [H ~> m or kg m-2]
  real :: ke_c_src, ke_c_tgt ! \int [u_c or v_c]^2 dz on src and tgt grids [H L2 T-2 ~> m3 s-2]
  real :: vel2h_tot     ! The vertically integrated velocity squared [H L2 T-2 ~> m3 s-2 or kg s-2]
  ! These column copies have a fixed size on GPU builds; see the note on fixed_col_extent.
  real :: h1(WSZK_(nz))      ! Source grid layer thicknesses [H ~> m or kg m-2]
  real :: h2(WSZK_(nz))      ! Target grid layer thicknesses [H ~> m or kg m-2]
  real :: vel_src(WSZK_(nz)) ! Velocities on the source grid [L T-1 ~> m s-1]
  real :: vel_tgt(WSZK_(nz)) ! Velocities remapped to the target grid [L T-1 ~> m s-1]
  integer :: k

  do k=1,nz
    h1(k) = h1_blk(ii,jj,k) ; h2(k) = h2_blk(ii,jj,k)
    vel_src(k) = vel_src_blk(ii,jj,k) ; vel_tgt(k) = vel_tgt_blk(ii,jj,k)
  enddo

  dvel2h_tot = 0.0
  if (do_vel2) then
    vel2h_tot = 0.
    do k=1,nz
      vel2h_tot = vel2h_tot - h1(k) * (vel_src(k)**2)
    enddo
  endif

  if (conserve_ke) then
  ! Conserve ke by correcting baroclinic component.
  ! Assumes total depth doesn't change during remap, and
  ! that \int u(z) dz doesn't change during remap.
    ! First get barotropic component
    vel_bt = 0.0
    do k=1,nz
      vel_bt = vel_bt + h2(k) * vel_tgt(k) ! Dimensions [H L T-1 ~> m2 s-1 or kg m-1 s-1]
    enddo
    h2_tot = 0.0
    do k=1,nz
      h2_tot = h2_tot + h2(k)
    enddo
    vel_bt = vel_bt / (h2_tot + H_subroundoff) ! Dimensions return to [L T-1 ~> m s-1]
    ! Next get baroclinic ke = \int (u-u_bt)^2 from source and target
    ke_c_src = 0.0
    ke_c_tgt = 0.0
    do k=1,nz
      ke_c_src = ke_c_src + h1(k) * (vel_src(k) - vel_bt)**2
      ke_c_tgt = ke_c_tgt + h2(k) * (vel_tgt(k) - vel_bt)**2
    enddo
    ! Next rescale baroclinic component on target grid to conserve ke
    ! The values 1.5625 = 1.25**2 and 1.25 below mean that the KE-conserving
    ! correction cannot amplify the baroclinic part of velocity by more
    ! than 25%. This threshold is somewhat arbitrary. It was added to
    ! prevent unstable behavior when the amplification factor is large.
    if (ke_c_src < 1.5625 * ke_c_tgt) then
      rescale_coef = sqrt(ke_c_src / ke_c_tgt)
    else
      rescale_coef = 1.25
    endif
    do k=1,nz
      vel_tgt(k) = vel_bt + rescale_coef * (vel_tgt(k) - vel_bt)
    enddo
  endif

  if (do_vel2) then
    do k=1,nz
      vel2h_tot = vel2h_tot + h2(k) * (vel_tgt(k)**2)
    enddo
    dvel2h_tot = vel2h_tot * I_dt
  endif

  if (mask_vel) call mask_near_bottom_vel(vel_tgt, h2, BBL_h_vel_mask, h_vel_mask, nz)

  do k=1,nz ; vel_tgt_blk(ii,jj,k) = vel_tgt(k) ; enddo

end subroutine remapped_vel_corrections

!> Zero out velocities in a column in very thin layers near the seafloor
pure subroutine mask_near_bottom_vel(vel, h, h_BBL, h_thin, nk)
  !$omp declare target
  integer, intent(in)    :: nk      !< The number of layers in this column
  real,    intent(inout) :: vel(nk) !< The velocity component being zeroed out [L T-1 ~> m s-1]
  real,    intent(in)    :: h(nk)   !< The layer thicknesses at velocity points  [H ~> m or kg m-2]
  real,    intent(in)    :: h_BBL   !< The thickness of the near-bottom region over which to apply
                                    !! the filtering [H ~> m or kg m-2]
  real,    intent(in)    :: h_thin  !< A layer thickness below which the filtering is applied [H ~> m or kg m-2]

  ! Local variables
  real :: h_from_bot  ! The distance between the top of a layer and the seafloor [H ~> m or kg m-2]
  integer :: k

  if ((h_BBL < 0.0) .or. (h_thin < 0.0)) return

  h_from_bot = 0.0
  do k=nk,1,-1
    h_from_bot = h_from_bot + h(k)
    if (h_from_bot > h_BBL) return
    ! Set the velocity to zero in thin, near-bottom layers.
    if (h(k) <= h_thin) vel(k) = 0.0
  enddo !k

end subroutine mask_near_bottom_vel


!> Remaps a single scalar between grids described by thicknesses h_src and h_dst.
!! h_dst must be dimensioned as a model array with GV%ke layers while h_src can
!! have an arbitrary number of layers specified by nk_src.
subroutine ALE_remap_scalar(CS, G, GV, nk_src, h_src, s_src, h_dst, s_dst, all_cells, old_remap)
  type(remapping_CS),                      intent(in)    :: CS        !< Remapping control structure
  type(ocean_grid_type),                   intent(in)    :: G         !< Ocean grid structure
  type(verticalGrid_type),                 intent(in)    :: GV        !< Ocean vertical grid structure
  integer,                                 intent(in)    :: nk_src    !< Number of levels on source grid
  real, dimension(SZI_(G),SZJ_(G),nk_src), intent(in)    :: h_src     !< Level thickness of source grid
                                                                      !! [H ~> m or kg m-2] or other units
                                                                      !! if H_neglect is provided
  real, dimension(SZI_(G),SZJ_(G),nk_src), intent(in)    :: s_src     !< Scalar on source grid, in arbitrary units [A]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)),intent(in)   :: h_dst     !< Level thickness of destination grid in the
                                                                      !! same units as h_src, often [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)),intent(inout) :: s_dst    !< Scalar on destination grid, in the same
                                                                      !! arbitrary units as s_src [A]
  logical, optional,                       intent(in)    :: all_cells !< If false, only reconstruct for
                                                                      !! non-vanished cells. Use all vanished
                                                                      !! layers otherwise (default).
  logical, optional,                       intent(in)    :: old_remap !< If true, use the old "remapping_core_w"
                                                                      !! method, otherwise use "remapping_core_h".
   ! Local variables
  integer :: i, j, k, n_points
  real :: dx(GV%ke+1) ! Change in interface position [H ~> m or kg m-2]
  logical :: ignore_vanished_layers, use_remapping_core_w

  ignore_vanished_layers = .false.
  if (present(all_cells)) ignore_vanished_layers = .not. all_cells
  use_remapping_core_w = .false.
  if (present(old_remap)) use_remapping_core_w = old_remap
  n_points = nk_src

  !$OMP parallel do default(shared) firstprivate(n_points,dx)
  do j = G%jsc,G%jec ; do i = G%isc,G%iec
    if (G%mask2dT(i,j) > 0.) then
      if (ignore_vanished_layers) then
        n_points = 0
        do k = 1, nk_src
          if (h_src(i,j,k)>0.) n_points = n_points + 1
        enddo
        s_dst(i,j,:) = 0.
      endif
      if (use_remapping_core_w) then
        call dzFromH1H2( n_points, h_src(i,j,1:n_points), GV%ke, h_dst(i,j,:), dx )
        call remapping_core_w(CS, n_points, h_src(i,j,1:n_points), s_src(i,j,1:n_points), &
                              GV%ke, dx, s_dst(i,j,:))
      else
        call remapping_core_h(CS, n_points, h_src(i,j,1:n_points), s_src(i,j,1:n_points), &
                              GV%ke, h_dst(i,j,:), s_dst(i,j,:))
      endif
    else
      s_dst(i,j,:) = 0.
    endif
  enddo ; enddo

end subroutine ALE_remap_scalar


!> Calculate edge values (top and bottom of layer) for T and S consistent with a PLM reconstruction
!! in the vertical direction. Boundary reconstructions are PCM unless bdry_extrap is true.
subroutine TS_PLM_edge_values( CS, S_t, S_b, T_t, T_b, G, GV, tv, h, bdry_extrap )
  type(ocean_grid_type),   intent(in)    :: G    !< ocean grid structure
  type(verticalGrid_type), intent(in)    :: GV   !< Ocean vertical grid structure
  type(ALE_CS),            intent(inout) :: CS   !< module control structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: S_t  !< Salinity at the top edge of each layer [S ~> ppt]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: S_b  !< Salinity at the bottom edge of each layer [S ~> ppt]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: T_t  !< Temperature at the top edge of each layer [C ~> degC]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: T_b  !< Temperature at the bottom edge of each layer [C ~> degC]
  type(thermo_var_ptrs),   intent(in)    :: tv   !< thermodynamics structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(in)    :: h    !< layer thickness [H ~> m or kg m-2]
  logical,                 intent(in)    :: bdry_extrap !< If true, use high-order boundary
                                                 !! extrapolation within boundary cells

  call ALE_PLM_edge_values( CS, G, GV, h, tv%S, bdry_extrap, S_t, S_b )
  call ALE_PLM_edge_values( CS, G, GV, h, tv%T, bdry_extrap, T_t, T_b )

end subroutine TS_PLM_edge_values

!> Calculate edge values (top and bottom of layer) 3d scalar array.
!! Boundary reconstructions are PCM unless bdry_extrap is true.
subroutine ALE_PLM_edge_values( CS, G, GV, h, Q, bdry_extrap, Q_t, Q_b )
  type(ALE_CS),            intent(in)    :: CS   !< module control structure
  type(ocean_grid_type),   intent(in)    :: G    !< ocean grid structure
  type(verticalGrid_type), intent(in)    :: GV   !< Ocean vertical grid structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(in)    :: h    !< layer thickness [H ~> m or kg m-2]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(in)    :: Q    !< 3d scalar array, in arbitrary units [A]
  logical,                 intent(in)    :: bdry_extrap !< If true, use high-order boundary
                                                 !! extrapolation within boundary cells
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: Q_t  !< Scalar at the top edge of each layer [A]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: Q_b  !< Scalar at the bottom edge of each layer [A]
  ! Local variables
  integer :: i, j, k
  real :: slp(GV%ke) ! Tracer slope times the cell width [A]
  real :: mslp       ! Monotonized tracer slope times the cell width [A]
  real :: h_neglect  ! Tiny thicknesses used in remapping [H ~> m or kg m-2]

  if (CS%answer_date >= 20190101) then
    h_neglect = GV%H_subroundoff
  elseif (GV%Boussinesq) then
    h_neglect = GV%m_to_H*1.0e-30
  else
    h_neglect = GV%kg_m2_to_H*1.0e-30
  endif

#ifdef __NVCOMPILER_OPENMP_GPU
  ! saw a bug on V100s running into illegal memory accesses, bind(parallel, teams) is used here
  ! as a solution to this bug due to a compiler bug, REVISIT
  !
  ! This gets run with team sizes of 1 because the functions aren't visible at compile time.
  ! It is therefore slow. Can be sped up by either inline (-Minline), or adding
  ! bind(parallel,teams) (an nvhpc extension, but unsupported by other compilers).
  !$omp target teams loop collapse(2) private(slp, mslp, k) bind(parallel,teams)
#else
  !$omp target teams loop collapse(2) private(slp, mslp, k)
#endif
  do j = G%jsc-1,G%jec+1 ; do i = G%isc-1,G%iec+1
    slp(1) = 0.
    do k = 2, GV%ke-1
      slp(k) = PLM_slope_wa(h(i,j,k-1), h(i,j,k), h(i,j,k+1), h_neglect, &
                            Q(i,j,k-1), Q(i,j,k), Q(i,j,k+1))
    enddo
    slp(GV%ke) = 0.

    do k = 2, GV%ke-1
      mslp = PLM_monotonized_slope(Q(i,j,k-1), Q(i,j,k), Q(i,j,k+1), slp(k-1), slp(k), slp(k+1))
      Q_t(i,j,k) = Q(i,j,k) - 0.5 * mslp
      Q_b(i,j,k) = Q(i,j,k) + 0.5 * mslp
    enddo
    if (bdry_extrap) then
      mslp = - PLM_extrapolate_slope(h(i,j,2), h(i,j,1), h_neglect, Q(i,j,2), Q(i,j,1))
      Q_t(i,j,1) = Q(i,j,1) - 0.5 * mslp
      Q_b(i,j,1) = Q(i,j,1) + 0.5 * mslp
      mslp = PLM_extrapolate_slope(h(i,j,GV%ke-1), h(i,j,GV%ke), h_neglect, &
                                   Q(i,j,GV%ke-1), Q(i,j,GV%ke))
      Q_t(i,j,GV%ke) = Q(i,j,GV%ke) - 0.5 * mslp
      Q_b(i,j,GV%ke) = Q(i,j,GV%ke) + 0.5 * mslp
    else
      Q_t(i,j,1) = Q(i,j,1)
      Q_b(i,j,1) = Q(i,j,1)
      Q_t(i,j,GV%ke) = Q(i,j,GV%ke)
      Q_b(i,j,GV%ke) = Q(i,j,GV%ke)
    endif

  enddo ; enddo

end subroutine ALE_PLM_edge_values

!> Calculate edge values (top and bottom of layer) for T and S consistent with a PPM reconstruction
!! in the vertical direction. Boundary reconstructions are PCM unless bdry_extrap is true.
subroutine TS_PPM_edge_values( CS, S_t, S_b, T_t, T_b, G, GV, tv, h, bdry_extrap )
  type(ocean_grid_type),   intent(in)    :: G    !< ocean grid structure
  type(verticalGrid_type), intent(in)    :: GV   !< Ocean vertical grid structure
  type(ALE_CS),            intent(inout) :: CS   !< module control structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: S_t  !< Salinity at the top edge of each layer [S ~> ppt]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: S_b  !< Salinity at the bottom edge of each layer [S ~> ppt]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: T_t  !< Temperature at the top edge of each layer [C ~> degC]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: T_b  !< Temperature at the bottom edge of each layer [C ~> degC]
  type(thermo_var_ptrs),   intent(in)    :: tv   !< thermodynamics structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(in)    :: h    !< layer thicknesses [H ~> m or kg m-2]
  logical,                 intent(in)    :: bdry_extrap !< If true, use high-order boundary
                                                 !! extrapolation within boundary cells

  ! Local variables
  integer :: i, j, k
  real    :: hTmp(GV%ke) ! A 1-d copy of h [H ~> m or kg m-2]
  real    :: tmp(GV%ke)  ! A 1-d copy of a column of temperature [C ~> degC] or salinity [S ~> ppt]
  real, dimension(CS%nk,2) :: &
      ppol_E            ! Edge value of polynomial in [C ~> degC] or [S ~> ppt]
  real, dimension(CS%nk,3) :: &
      ppol_coefs        ! Coefficients of polynomial, all in [C ~> degC] or [S ~> ppt]
  real :: h_neglect, h_neglect_edge ! Tiny thicknesses [H ~> m or kg m-2]

  if (CS%answer_date >= 20190101) then
    h_neglect = GV%H_subroundoff ; h_neglect_edge = GV%H_subroundoff
  elseif (GV%Boussinesq) then
    h_neglect = GV%m_to_H*1.0e-30 ; h_neglect_edge = GV%m_to_H*1.0e-10
  else
    h_neglect = GV%kg_m2_to_H*1.0e-30 ; h_neglect_edge = GV%kg_m2_to_H*1.0e-10
  endif

  ! Determine reconstruction within each column
  !$OMP parallel do default(shared) private(hTmp,tmp,ppol_E,ppol_coefs)
  do j = G%jsc-1,G%jec+1 ; do i = G%isc-1,G%iec+1

    ! Build current grid
    hTmp(:) = h(i,j,:)
    tmp(:) = tv%S(i,j,:)

    ! Reconstruct salinity profile
    ppol_E(:,:) = 0.0
    ppol_coefs(:,:) = 0.0
    call edge_values_implicit_h4( GV%ke, hTmp, tmp, ppol_E, h_neglect=h_neglect_edge, &
                                  answer_date=CS%answer_date )
    call PPM_reconstruction( GV%ke, hTmp, tmp, ppol_E, ppol_coefs, h_neglect, &
                                  answer_date=CS%answer_date )
    if (bdry_extrap) &
        call PPM_boundary_extrapolation( GV%ke, hTmp, tmp, ppol_E, ppol_coefs, h_neglect )

    do k = 1,GV%ke
      S_t(i,j,k) = ppol_E(k,1)
      S_b(i,j,k) = ppol_E(k,2)
    enddo

    ! Reconstruct temperature profile
    ppol_E(:,:) = 0.0
    ppol_coefs(:,:) = 0.0
    tmp(:) = tv%T(i,j,:)
    if (CS%answer_date < 20190101) then
      call edge_values_implicit_h4( GV%ke, hTmp, tmp, ppol_E, h_neglect=1.0e-10*GV%m_to_H, &
                                  answer_date=CS%answer_date )
    else
      call edge_values_implicit_h4( GV%ke, hTmp, tmp, ppol_E, h_neglect=GV%H_subroundoff, &
                                  answer_date=CS%answer_date )
    endif
    call PPM_reconstruction( GV%ke, hTmp, tmp, ppol_E, ppol_coefs, h_neglect, &
                                  answer_date=CS%answer_date )
    if (bdry_extrap) &
        call PPM_boundary_extrapolation(GV%ke, hTmp, tmp, ppol_E, ppol_coefs, h_neglect )

    do k = 1,GV%ke
      T_t(i,j,k) = ppol_E(k,1)
      T_b(i,j,k) = ppol_E(k,2)
    enddo

  enddo ; enddo

end subroutine TS_PPM_edge_values

!> Calculate edge values (top and bottom of layer) for T and S consistent with a PLM reconstruction
!! in the vertical direction that uses weighted least squares for the slope.
subroutine TS_PLM_WLS_edge_values(CS, S_t, S_b, T_t, T_b, G, GV, tv, h)
  type(ocean_grid_type),   intent(in)    :: G    !< ocean grid structure
  type(verticalGrid_type), intent(in)    :: GV   !< Ocean vertical grid structure
  type(ALE_CS),            intent(inout) :: CS   !< module control structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: S_t  !< Salinity at the top edge of each layer [S ~> ppt]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: S_b  !< Salinity at the bottom edge of each layer [S ~> ppt]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: T_t  !< Temperature at the top edge of each layer [C ~> degC]
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(inout) :: T_b  !< Temperature at the bottom edge of each layer [C ~> degC]
  type(thermo_var_ptrs),   intent(in)    :: tv   !< thermodynamics structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), &
                           intent(in)    :: h    !< layer thickness [H ~> m or kg m-2]
  ! Local variables
  integer :: i, j, k
  type(PLM_WLS) :: recon !< A PLM-WLS reconstruction

  call recon%init(GV%ke, h_neglect=GV%H_subroundoff)

  !$OMP parallel do default(shared) firstprivate(recon)
  do j = G%jsc-1,G%jec+1 ; do i = G%isc-1,G%iec+1

    call recon%reconstruct(h(i,j,:), tv%T(i,j,:))
    T_t(i,j,:) = recon%ul(:)
    T_b(i,j,:) = recon%ur(:)

    call recon%reconstruct(h(i,j,:), tv%S(i,j,:))
    S_t(i,j,:) = recon%ul(:)
    S_b(i,j,:) = recon%ur(:)

  enddo ; enddo

  call recon%destroy()

end subroutine TS_PLM_WLS_edge_values

!> Initializes regridding for the main ALE algorithm
subroutine ALE_initRegridding(G, GV, US, max_depth, param_file, mdl, regridCS)
  type(ocean_grid_type),   intent(in)  :: G          !< Grid structure
  type(verticalGrid_type), intent(in)  :: GV         !< Ocean vertical grid structure
  type(unit_scale_type),   intent(in)  :: US         !< A dimensional unit scaling type
  real,                    intent(in)  :: max_depth  !< The maximum depth of the ocean [Z ~> m].
  type(param_file_type),   intent(in)  :: param_file !< parameter file
  character(len=*),        intent(in)  :: mdl        !< Name of calling module
  type(regridding_CS),     intent(out) :: regridCS   !< Regridding parameters and work arrays
  ! Local variables
  character(len=30) :: coord_mode

  call get_param(param_file, mdl, "REGRIDDING_COORDINATE_MODE", coord_mode, &
                 "Coordinate mode for vertical regridding. "//&
                 "Choose among the following possibilities: "//&
                 trim(regriddingCoordinateModeDoc), &
                 default=DEFAULT_COORDINATE_MODE, fail_if_missing=.true.)

  call initialize_regridding(regridCS, G, GV, US, max_depth, param_file, mdl, coord_mode, '', '')

end subroutine ALE_initRegridding

!> Query the target coordinate interfaces positions
function ALE_getCoordinate( CS )
  type(ALE_CS), pointer    :: CS                  !< module control structure

  real, dimension(CS%nk+1) :: ALE_getCoordinate !< The coordinate positions, in the appropriate units
                                                !! of the target coordinate, e.g. [Z ~> m] for z*,
                                                !! non-dimensional for sigma, etc.
  ALE_getCoordinate(:) = getCoordinateInterfaces( CS%regridCS, undo_scaling=.true. )

end function ALE_getCoordinate


!> Query the target coordinate units
function ALE_getCoordinateUnits( CS )
  type(ALE_CS), pointer :: CS   !< module control structure

  character(len=20)     :: ALE_getCoordinateUnits

  ALE_getCoordinateUnits = getCoordinateUnits( CS%regridCS )

end function ALE_getCoordinateUnits


!> Returns true if initial conditions should be regridded and remapped
logical function ALE_remap_init_conds( CS )
  type(ALE_CS), pointer :: CS   !< module control structure

  ALE_remap_init_conds = .false.
  if (associated(CS)) ALE_remap_init_conds = CS%remap_after_initialization
end function ALE_remap_init_conds

!> Updates the weights for time filtering the new grid generated in regridding
subroutine ALE_update_regrid_weights( dt, CS )
  real,         intent(in) :: dt !< Time-step used between ALE calls [T ~> s]
  type(ALE_CS), pointer    :: CS !< ALE control structure
  ! Local variables
  real :: w  ! An implicit weighting estimate [nondim]

  if (associated(CS)) then
    w = 0.0
    if (CS%regrid_time_scale > 0.0) then
      w = CS%regrid_time_scale / (CS%regrid_time_scale + dt)
    endif
    call set_regrid_params(CS%regridCS, old_grid_weight=w)
  endif

end subroutine ALE_update_regrid_weights

!> Update the vertical grid type with ALE information.
!! This subroutine sets information in the verticalGrid_type to be
!! consistent with the use of ALE mode.
subroutine ALE_updateVerticalGridType(CS, GV)
  type(ALE_CS),            pointer :: CS  !< ALE control structure
  type(verticalGrid_type), pointer :: GV  !< vertical grid information

  integer :: nk

  nk = GV%ke
  GV%sInterface(1:nk+1) = getCoordinateInterfaces( CS%regridCS, undo_scaling=.true. )
  GV%sLayer(1:nk) = 0.5*( GV%sInterface(1:nk) + GV%sInterface(2:nk+1) )
  GV%zAxisUnits = getCoordinateUnits( CS%regridCS )
  GV%zAxisLongName = getCoordinateShortName( CS%regridCS )
  GV%direction = -1 ! Because of ferret in z* mode. Need method to set
                    ! as function of coordinate mode.

end subroutine ALE_updateVerticalGridType


!> Write the vertical coordinate information into a file.
!! This subroutine writes out a file containing any available data related
!! to the vertical grid used by the MOM ocean model when in ALE mode.
subroutine ALE_writeCoordinateFile( CS, GV, directory )
  type(ALE_CS),            pointer     :: CS         !< module control structure
  type(verticalGrid_type), intent(in)  :: GV         !< ocean vertical grid structure
  character(len=*),        intent(in)  :: directory  !< directory for writing grid info

  character(len=240) :: filepath

  filepath = trim(directory) // trim("Vertical_coordinate.nc")

  call write_regrid_file(CS%regridCS, GV, filepath)

end subroutine ALE_writeCoordinateFile

!> Set h to coordinate values for fixed coordinate systems
subroutine ALE_initThicknessToCoord( CS, G, GV, h, height_units )
  type(ALE_CS), intent(inout)                            :: CS  !< module control structure
  type(ocean_grid_type), intent(in)                      :: G   !< module grid structure
  type(verticalGrid_type), intent(in)                    :: GV  !< Ocean vertical grid structure
  real, dimension(SZI_(G),SZJ_(G),SZK_(GV)), intent(out) :: h   !< layer thickness in thickness units
                                                                !! [H ~> m or kg m-2] or height units [Z ~> m]
  logical,                          optional, intent(in) :: height_units !< If present and true, the
                                                                !! thicknesses are in height units

  ! Local variables
  real :: scale ! A scaling value for the thicknesses [nondim] or [H Z-1 ~> nondim or kg m-3]
  integer :: i, j

  scale = GV%Z_to_H
  if (present(height_units)) then ; if (height_units) scale = 1.0 ; endif
  do j = G%jsd,G%jed ; do i = G%isd,G%ied
    h(i,j,:) = scale * getStaticThickness( CS%regridCS, 0., max(G%meanSL(i,j)+G%bathyT(i,j), 0.0) )
  enddo ; enddo

end subroutine ALE_initThicknessToCoord

end module MOM_ALE
