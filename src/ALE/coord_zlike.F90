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

public init_coord_zlike, set_zlike_params, build_zstar_column, build_zstar_columns, end_coord_zlike

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

!> Builds a z* coordinate with a minimum thickness
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
  ! Local variables
  real :: eta   ! Free surface height [Z ~> m] or [H ~> m or kg m-2]
  real :: z0_top, z_scale ! Thicknesses or heights [Z ~> m] or [H ~> m or kg m-2]
  logical :: new_zstar_def

  z_scale = 1.0 ; if (present(zScale)) z_scale = zScale

  new_zstar_def = .false.
  z0_top = 0.
  if (present(z_rigid_top)) then
    z0_top = z_rigid_top
    new_zstar_def = .true.
  endif

  ! Position of free-surface (or the rigid top, for which eta ~ z0_top)
  eta = total_thickness - depth
  if (present(eta_orig)) eta = eta_orig

  call zstar_column(CS%nk, 1, 1, 1, 1, CS%coordinateResolution, CS%min_thickness, depth, total_thickness, &
                    z0_top, eta, z_scale, new_zstar_def, zInterface)

end subroutine build_zstar_column

!> Builds z* coordinates with a minimum thickness in a block of columns, without a rigid top.
!! This is build_zstar_column applied to every column of the block where mask > 0.  The block
!! arrays have the column index last, so that neighboring columns are adjacent in memory.
subroutine build_zstar_columns(CS, nib, njb, iie, jje, mask, depth, total_thickness, zInterface, zScale)
  type(zlike_CS),           intent(in)    :: CS  !< Coordinate control structure
  integer,                  intent(in)    :: nib !< The i-size of the block arrays
  integer,                  intent(in)    :: njb !< The j-size of the block arrays
  integer,                  intent(in)    :: iie !< The number of valid columns in the i-direction
  integer,                  intent(in)    :: jje !< The number of valid columns in the j-direction
  real, dimension(nib,njb), intent(in)    :: mask !< Columns are only built where mask > 0 [nondim]
  real, dimension(nib,njb), intent(in)    :: depth !< Depth of ocean bottom (positive downward in the
                                                   !! output units), units may be [Z ~> m] or [H ~> m or kg m-2]
  real, dimension(nib,njb), intent(in)    :: total_thickness !< Column thickness (positive definite in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real, dimension(nib,njb,CS%nk+1), &
                            intent(inout) :: zInterface !< Absolute positions of interfaces (in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real,                     intent(in)    :: zScale !< Scaling factor from the target coordinate resolution
                                                    !! in Z to desired units for zInterface, perhaps Z_to_H,
                                                    !! often [nondim] or [H Z-1 ~> 1 or kg m-3]
  ! Local variables
  real :: coord_res(CS%nk) ! A copy of the target coordinate resolution, usually in [Z ~> m]
  real :: min_thickness    ! The minimum layer thickness [Z ~> m] or [H ~> m or kg m-2]
  integer :: nk      ! The number of layers of the new grid
  integer :: ii, jj  ! The indices of a column within the block

  nk = CS%nk ; min_thickness = CS%min_thickness
  coord_res(:) = CS%coordinateResolution(:)

  !$omp target enter data map(to: coord_res)
  do concurrent (jj=1:jje, ii=1:iie, mask(ii,jj) > 0.0)
    call zstar_column(nk, nib, njb, ii, jj, coord_res, min_thickness, depth(ii,jj), total_thickness(ii,jj), &
                      0., total_thickness(ii,jj) - depth(ii,jj), zScale, .false., zInterface)
  enddo
  !$omp target exit data map(delete: coord_res)

end subroutine build_zstar_columns

!> Builds a z* coordinate with a minimum thickness in the column (ii,jj) of a block of columns.
!! This is the column code shared by build_zstar_column, which passes a single column as a
!! 1x1 block, and build_zstar_columns.
pure subroutine zstar_column(nk, nib, njb, ii, jj, coordinateResolution, CS_min_thickness, depth, &
                             total_thickness, z0_top, eta, z_scale, new_zstar_def, zInterface)
  !$omp declare target
  integer,               intent(in)    :: nk !< Number of levels to be generated
  integer,               intent(in)    :: nib !< The i-size of the block of columns
  integer,               intent(in)    :: njb !< The j-size of the block of columns
  integer, value                       :: ii  !< The block-local i index of the column
  integer, value                       :: jj  !< The block-local j index of the column
  real, dimension(nk),   intent(in)    :: coordinateResolution !< Target coordinate resolution, usually in [Z ~> m]
  real,                  intent(in)    :: CS_min_thickness !< Minimum allowed thickness, in the same units
                                                   !! as depth [Z ~> m] or [H ~> m or kg m-2]
  real,                  intent(in)    :: depth !< Depth of ocean bottom (positive downward in the
                                                   !! output units), units may be [Z ~> m] or [H ~> m or kg m-2]
  real,                  intent(in)    :: total_thickness !< Column thickness (positive definite in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real,                  intent(in)    :: z0_top !< The height of a rigid top, or 0 (positive upward in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real,                  intent(in)    :: eta !< Free surface height (in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  real,                  intent(in)    :: z_scale !< Scaling factor from the target coordinate resolution
                                                    !! in Z to desired units for zInterface, perhaps Z_to_H,
                                                    !! often [nondim] or [H Z-1 ~> 1 or kg m-3]
  logical,               intent(in)    :: new_zstar_def !< If true, use the definition with a rigid top
  real, dimension(nib,njb,nk+1), &
                         intent(inout) :: zInterface !< Absolute positions of interfaces (in the same
                                                   !! units as depth) [Z ~> m] or [H ~> m or kg m-2]
  ! Local variables
  real :: stretching ! A stretching factor for the coordinate [nondim]
  real :: dh, min_thickness, z_star ! Thicknesses or heights [Z ~> m] or [H ~> m or kg m-2]
  integer :: k

  min_thickness = min( CS_min_thickness, total_thickness/real(nk) )

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
    zInterface(ii,jj,1) = eta ! The actual position of the top of the column
    do k = 2,nk
      z_star = z_star - coordinateResolution(k-1)*z_scale
      ! This ensures that z is below a rigid upper surface (ice shelf bottom)
      zInterface(ii,jj,k) = min( eta + stretching * ( z_star - z0_top ), z0_top )
      ! This ensures that the layer in inflated
      zInterface(ii,jj,k) = min( zInterface(ii,jj,k), zInterface(ii,jj,k-1) - min_thickness )
      ! This ensures that z is above or at the topography
      zInterface(ii,jj,k) = max( zInterface(ii,jj,k), -depth + real(nk+1-k) * min_thickness )
    enddo
    zInterface(ii,jj,nk+1) = -depth

  else
    ! Integrate down from the top for a notional new grid, ignoring topography
    ! The starting position is offset by z0_top which, if z0_top<0, will place
    ! interfaces above the rigid boundary.
    zInterface(ii,jj,1) = eta
    do k = 1,nk
      dh = stretching * coordinateResolution(k)*z_scale ! Notional grid spacing
      zInterface(ii,jj,k+1) = zInterface(ii,jj,k) - dh
    enddo

    ! Integrating up from the bottom adjusting interface position to accommodate
    ! inflating layers without disturbing the interface above
    zInterface(ii,jj,nk+1) = -depth
    do k = nk,1,-1
      if ( zInterface(ii,jj,k) < (zInterface(ii,jj,k+1) + min_thickness) ) then
        zInterface(ii,jj,k) = zInterface(ii,jj,k+1) + min_thickness
      endif
    enddo
  endif

end subroutine zstar_column

end module coord_zlike
