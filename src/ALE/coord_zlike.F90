! This file is part of MOM6, the Modular Ocean Model version 6.
! See the LICENSE file for licensing information.
! SPDX-License-Identifier: Apache-2.0

!> Regrid columns for a z-like coordinate (z-star, z-level)
module coord_zlike

use MOM_error_handler, only : MOM_error, FATAL

implicit none ; private

!> Control structure containing required parameters for a z-like coordinate
type, public :: zlike_CS ; private

  !> Number of levels to be generated
  integer :: nk

  !> Minimum thickness allowed for layers, in the same thickness units (perhaps [H ~> m or kg m-2])
  !! that will be used in all subsequent calls to build_zstar_column with this structure.
  real :: min_thickness

  !> Target coordinate resolution, usually in [Z ~> m]
  real, allocatable, dimension(:) :: coordinateResolution
end type zlike_CS

public init_coord_zlike, set_zlike_params, build_zstar_column, build_zstar_column_loc
public get_zlike_coord_res, end_coord_zlike

contains

!> Initialise a zlike_CS with pointers to parameters
subroutine init_coord_zlike(CS, nk, coordinateResolution)
  type(zlike_CS),     pointer    :: CS !< Unassociated pointer to hold the control structure
  integer,            intent(in) :: nk !< Number of levels in the grid
  real, dimension(:), intent(in) :: coordinateResolution !< Target coordinate resolution [Z ~> m]

  if (associated(CS)) call MOM_error(FATAL, "init_coord_zlike: CS already associated!")
  allocate(CS)
  allocate(CS%coordinateResolution(nk))

  CS%nk                   = nk
  CS%coordinateResolution = coordinateResolution
end subroutine init_coord_zlike

!> Deallocates the zlike control structure
subroutine end_coord_zlike(CS)
  type(zlike_CS), pointer :: CS !< Coordinate control structure

  ! Nothing to do
  if (.not. associated(CS)) return
  deallocate(CS%coordinateResolution)
  deallocate(CS)
end subroutine end_coord_zlike

!> Set parameters in the zlike structure
subroutine set_zlike_params(CS, min_thickness)
  type(zlike_CS), pointer    :: CS !< Coordinate control structure
  real, optional, intent(in) :: min_thickness !< Minimum allowed thickness [H ~> m or kg m-2]

  if (.not. associated(CS)) call MOM_error(FATAL, "set_zlike_params: CS not associated")

  if (present(min_thickness)) CS%min_thickness = min_thickness
end subroutine set_zlike_params

!> Builds a z* coordinate with a minimum thickness (thin wrapper preserving the CS-taking API;
!! the body lives in the device-callable build_zstar_column_loc, GPU port increment 1).
subroutine build_zstar_column(CS, depth, total_thickness, zInterface, &
                              z_rigid_top, eta_orig, zScale)
  type(zlike_CS),           intent(in)    :: CS !< Coordinate control structure
  real,                     intent(in)    :: depth !< Depth of ocean bottom (positive downward in the
                                                   !! output units), units may be [Z ~> m] or [H ~> m or kg m-2]
  real,                     intent(in)    :: total_thickness !< Column thickness (positive definite in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real, dimension(CS%nk+1), intent(inout) :: zInterface !< Absolute positions of interfaces (in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real, optional,           intent(in)    :: z_rigid_top !< The height of a rigid top (positive upward in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real, optional,           intent(in)    :: eta_orig !< The actual original height of the top (in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real, optional,           intent(in)    :: zScale !< Scaling factor from the target coordinate resolution
                                                    !! in Z to desired units for zInterface, perhaps Z_to_H,
                                                    !! often [nondim] or [H Z-1 ~> 1 or kg m-3]
  real :: z_scale_w ! zScale with its default resolved on the host

  z_scale_w = 1.0 ; if (present(zScale)) z_scale_w = zScale
  call build_zstar_column_loc(CS%nk, CS%min_thickness, CS%coordinateResolution, depth, &
                              total_thickness, zInterface, z_scale_w, z_rigid_top, eta_orig)

end subroutine build_zstar_column

!> Copy the target coordinate resolution out of a zlike_CS (a private component), for callers that
!! need it as a plain array -- e.g. to hoist it onto a device region without dereferencing the CS.
subroutine get_zlike_coord_res(CS, coordinateResolution)
  type(zlike_CS),     intent(in)  :: CS !< Coordinate control structure
  real, dimension(:), intent(out) :: coordinateResolution !< Target coordinate resolution [Z ~> m]
  integer :: k
  do k=1,CS%nk ; coordinateResolution(k) = CS%coordinateResolution(k) ; enddo
end subroutine get_zlike_coord_res

!> Builds a z* coordinate with a minimum thickness.  This is the element-wise, control-structure-free
!! form of build_zstar_column: it takes the (host-resolved) scalar and array parameters explicitly so
!! it can be made device-callable, avoiding a dereference of the nested (pointer + allocatable) zlike_CS
!! inside a device region.  The arithmetic is verbatim from the former build_zstar_column body.
subroutine build_zstar_column_loc(nk, min_thick, coordinateResolution, depth, total_thickness, &
                                  zInterface, z_scale, z_rigid_top, eta_orig)
  integer,                  intent(in)    :: nk !< Number of levels to be generated
  real,                     intent(in)    :: min_thick !< Minimum thickness allowed for layers, in the
                                                   !! same units as depth [Z ~> m] or [H ~> m or kg m-2]
  real, dimension(nk),      intent(in)    :: coordinateResolution !< Target coordinate resolution [Z ~> m]
  real,                     intent(in)    :: depth !< Depth of ocean bottom (positive downward in the
                                                   !! output units), units may be [Z ~> m] or [H ~> m or kg m-2]
  real,                     intent(in)    :: total_thickness !< Column thickness (positive definite in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real, dimension(nk+1),    intent(inout) :: zInterface !< Absolute positions of interfaces (in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real,                     intent(in)    :: z_scale !< Scaling factor from the target coordinate resolution
                                                   !! in Z to desired units for zInterface (was optional zScale;
                                                   !! required here so device call sites need no keyword args)
  real, optional,           intent(in)    :: z_rigid_top !< The height of a rigid top (positive upward in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real, optional,           intent(in)    :: eta_orig !< The actual original height of the top (in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  ! Local variables
  real :: eta   ! Free surface height [Z ~> m] or [H ~> m or kg m-2]
  real :: stretching ! A stretching factor for the coordinate [nondim]
  real :: dh, min_thickness, z0_top, z_star ! Thicknesses or heights [Z ~> m] or [H ~> m or kg m-2]
  integer :: k
  logical :: new_zstar_def
  !$omp declare target

  new_zstar_def = .false.
  min_thickness = min( min_thick, total_thickness/real(nk) )
  z0_top = 0.
  if (present(z_rigid_top)) then
    z0_top = z_rigid_top
    new_zstar_def = .true.
  endif

  ! Position of free-surface (or the rigid top, for which eta ~ z0_top)
  eta = total_thickness - depth
  if (present(eta_orig)) eta = eta_orig

  ! Conventional z* coordinate:
  !   z* = (z-eta) / stretching   where stretching = (H+eta)/H
  !   z = eta + stretching * z*
  ! The above gives z*(z=eta) = 0, z*(z=-H) = -H.
  ! With a rigid top boundary at eta = z0_top then
  !   z* = z0 + (z-eta) / stretching   where stretching = (H+eta)/(H+z0)
  !   z = eta + stretching * (z*-z0) * stretching
  stretching = total_thickness / ( depth + z0_top )

  if (new_zstar_def) then
    ! z_star is the notional z* coordinate in absence of upper/lower topography
    z_star = 0. ! z*=0 at the free-surface
    zInterface(1) = eta ! The actual position of the top of the column
    do k = 2,nk
      z_star = z_star - coordinateResolution(k-1)*z_scale
      ! This ensures that z is below a rigid upper surface (ice shelf bottom)
      zInterface(k) = min( eta + stretching * ( z_star - z0_top ), z0_top )
      ! This ensures that the layer in inflated
      zInterface(k) = min( zInterface(k), zInterface(k-1) - min_thickness )
      ! This ensures that z is above or at the topography
      zInterface(k) = max( zInterface(k), -depth + real(nk+1-k) * min_thickness )
    enddo
    zInterface(nk+1) = -depth

  else
    ! Integrate down from the top for a notional new grid, ignoring topography
    ! The starting position is offset by z0_top which, if z0_top<0, will place
    ! interfaces above the rigid boundary.
    zInterface(1) = eta
    do k = 1,nk
      dh = stretching * coordinateResolution(k)*z_scale ! Notional grid spacing
      zInterface(k+1) = zInterface(k) - dh
    enddo

    ! Integrating up from the bottom adjusting interface position to accommodate
    ! inflating layers without disturbing the interface above
    zInterface(nk+1) = -depth
    do k = nk,1,-1
      if ( zInterface(k) < (zInterface(k+1) + min_thickness) ) then
        zInterface(k) = zInterface(k+1) + min_thickness
      endif
    enddo
  endif

end subroutine build_zstar_column_loc

end module coord_zlike
