#line "/lustre/orion/csc693/scratch/jg4/mom/MOM6-examples/src/MOM6/src/tracer/MOM_tracer_advect.F90" 8
      module MOM_tracer_advect

      use MOM_cpu_clock, only : cpu_clock_id, cpu_clock_begin, cpu_clock&
     &_end
#line 11
      use MOM_cpu_clock, only : CLOCK_MODULE, CLOCK_ROUTINE
      use MOM_diag_mediator, only : post_data, query_averaging_enabled, &
     &diag_ctrl
#line 13
      use MOM_diag_mediator, only : register_diag_field, safe_alloc_ptr,&
     & time_type
#line 14
      use MOM_domains,   only : sum_across_PEs, max_across_PEs
      use MOM_domains,   only : create_group_pass, do_group_pass, group_&
     &pass_type, pass_var
#line 16
      use MOM_error_handler, only : MOM_error, FATAL, WARNING, MOM_mesg,&
     & is_root_pe
#line 17
      use MOM_file_parser, only : get_param, log_version, param_file_typ&
     &e
#line 18
      use MOM_grid,      only : ocean_grid_type
      use MOM_open_boundary, only : ocean_OBC_type, OBC_NONE, OBC_DIRECT&
     &ION_E
#line 20
      use MOM_open_boundary, only : OBC_DIRECTION_W, OBC_DIRECTION_N, OB&
     &C_DIRECTION_S
#line 21
      use MOM_open_boundary, only : OBC_segment_type
      use MOM_tracer_registry, only : tracer_registry_type, tracer_type
      use MOM_unit_scaling, only : unit_scale_type
      use MOM_verticalGrid, only : verticalGrid_type
      use MOM_tracer_advect_schemes, only : ADVECT_PLM, ADVECT_PPMH3, AD&
     &VECT_PPM
#line 26
      use MOM_tracer_advect_schemes, only : set_tracer_advect_scheme, Tr&
     &acerAdvectionSchemeDoc
#line 27
      implicit none ; private



      public advect_tracer
      public tracer_advect_init
      public tracer_advect_end


      type, public :: tracer_advect_CS ; private
      real :: dt
      type(diag_ctrl), pointer :: diag

      logical :: debug
      logical :: useHuynhStencilBug = .false.

      type(group_pass_type) :: pass_uhr_vhr_t_hprev
      integer :: default_advect_scheme = -1
      integer :: nkblock

      end type tracer_advect_CS


      integer :: id_clock_advect
      integer :: id_clock_pass
      integer :: id_clock_sync


      contains



      subroutine advect_tracer(h_end, uhtr, vhtr, OBC, dt, G, GV, US, CS&
     &, Reg, x_first_in, vol_prev, max_iter_in, update_vol_prev, uhr_out&
     &, vhr_out, flux_type)
      type(ocean_grid_type), intent(inout) :: G
      type(verticalGrid_type), intent(in) :: GV
      real, dimension(G%isd:G%ied,G%jsd:G%jed,GV%ke), intent(in) :: h_en&
     &d
      real, dimension(G%IsdB:G%IedB,G%jsd:G%jed,GV%ke), intent(in) :: uh&
     &tr

      real, dimension(G%isd:G%ied,G%JsdB:G%JedB,GV%ke), intent(in) :: vh&
     &tr

      type(ocean_OBC_type), pointer      :: OBC
      real,                intent(in)    :: dt
      type(unit_scale_type), intent(in)  :: US
      type(tracer_advect_CS), pointer    :: CS
      type(tracer_registry_type), pointer :: Reg
      logical,   optional, intent(in)    :: x_first_in


      real, dimension(G%isd:G%ied,G%jsd:G%jed,GV%ke), optional, intent(i&
     &nout) :: vol_prev




      integer,   optional, intent(in)    :: max_iter_in
      logical,   optional, intent(in)    :: update_vol_prev

      real, dimension(G%IsdB:G%IedB,G%jsd:G%jed,GV%ke), optional, intent&
     &(out) :: uhr_out

      real, dimension(G%isd:G%ied,G%JsdB:G%JedB,GV%ke), optional, intent&
     &(out) :: vhr_out




      integer,   optional, intent(in)    :: flux_type




      integer :: flux_type_ctrl
      real, dimension(G%isd:G%ied,G%jsd:G%jed,GV%ke) :: hprev

      real, dimension(G%IsdB:G%IedB,G%jsd:G%jed,GV%ke) :: uhr

      real, dimension(G%isd:G%ied,G%JsdB:G%JedB,GV%ke) :: vhr

      real :: uh_neglect(G%IsdB:G%IedB,G%jsd:G%jed)
      real :: vh_neglect(G%isd:G%ied,G%JsdB:G%JedB)


      real :: landvolfill
      logical :: use_PPM_stencil
      real :: Idt
      logical :: domore_u(G%jsd:G%jed,GV%ke)
      logical :: domore_v(G%JsdB:G%JedB,GV%ke)
      logical :: x_first
      logical :: advect_this_tracer(Reg%ntr)





      integer :: max_iter
      integer :: domore_k(GV%ke)
      integer :: stencil
      integer :: nsten_halo
      integer :: i, j, k, kk, m, is, ie, js, je, isd, ied, jsd, jed, nz,&
     & itt, ntr, do_any
#line 131
      integer :: isv, iev, jsv, jev
      integer :: IsdB, IedB, JsdB, JedB
      integer :: stencil_local
      integer :: local_advect_scheme(Reg%ntr)
      integer :: domore_k_tmp
      integer :: nkk
      integer :: ksb, keb
      integer :: kke

      is = G%isc ; ie = G%iec ; js = G%jsc ; je = G%jec ; nz = GV%ke
      isd = G%isd ; ied = G%ied ; jsd = G%jsd ; jed = G%jed
      IsdB = G%IsdB ; IedB = G%IedB ; JsdB = G%JsdB ; JedB = G%JedB
      landvolfill = 1.0e-20
      stencil = 2

      ntr = Reg%ntr
      Idt = 1.0 / dt

      if(.not. associated(CS)) call MOM_error(FATAL, "MOM_tracer_advect:&
     & "// "tracer_advect_init must be called before advect_tracer.")
      if(.not. associated(Reg)) call MOM_error(FATAL, "MOM_tracer_advect&
     &: "// "register_tracer must be called before advect_tracer.")
      if(Reg%ntr==0) return

      nkk = CS%nkblock
      if(nkk == 0) nkk = nz

!$omp   target enter data map(to: OBC, Reg, Reg%Tr(:))
!$omp   target enter data map(alloc: domore_u, domore_v, uhr, vhr, uh_ne&
!$omp&glect, vh_neglect, hprev, local_advect_scheme, advect_this_tracer)

      do concurrent(k=1:nz, j=jsd:jed)
      domore_u(j,k) = .false.
      enddo
      do concurrent(k=1:nz, j=jsdB:jedB)
      domore_v(j,k) = .false.
      enddo
      do concurrent(m=1:ntr)
      advect_this_tracer(m) = .false.
      enddo

      call cpu_clock_begin(id_clock_advect)
      x_first =(MOD(G%first_direction,2) == 0)


      do concurrent(m = 1:ntr)

      local_advect_scheme(m) = Reg%Tr(m)%advect_scheme
      if(local_advect_scheme(m) < 0) local_advect_scheme(m) = CS%default&
     &_advect_scheme
      if(local_advect_scheme(m) == ADVECT_PLM) then
       stencil_local = 2
      elseif(local_advect_scheme(m) == ADVECT_PPM) then
       stencil_local = 3
      elseif(local_advect_scheme(m) == ADVECT_PPMH3) then
       if (CS%useHuynhStencilBug) then
         stencil_local = 2
       else
         stencil_local = 3
       endif
      endif
      stencil = max(stencil, stencil_local)
      enddo

!$omp   target update from(local_advect_scheme)

      if(min(is-isd,ied-ie,js-jsd,jed-je) < stencil) then
      call MOM_error(FATAL, "MOM_tracer_advect: "// "stencil is wider th&
     &an the halo.")
      endif

      max_iter = 2*INT(CEILING(dt/CS%dt)) + 1

      if(present(max_iter_in)) max_iter = max_iter_in
      if(present(x_first_in)) x_first = x_first_in

      flux_type_ctrl = 0
      if(present(flux_type)) flux_type_ctrl = flux_type

      call cpu_clock_begin(id_clock_pass)
      call create_group_pass(CS%pass_uhr_vhr_t_hprev, uhr, vhr, G%Domain&
     &)
#line 212
      call create_group_pass(CS%pass_uhr_vhr_t_hprev, hprev, G%Domain)
      do m=1,ntr
      call create_group_pass(CS%pass_uhr_vhr_t_hprev, Reg%Tr(m)%t, G%Dom&
     &ain)
#line 215
      enddo
      call cpu_clock_end(id_clock_pass)



      do concurrent(k=1:nz)
      do concurrent(j=jsd:jed, I=IsdB:IedB)
      uhr(I,j,k) = 0.0
      enddo
      do concurrent(J=jsdB:jedB, i=Isd:Ied)
      vhr(i,J,k) = 0.0
      enddo
      do concurrent(j=jsd:jed, i=Isd:Ied)
      hprev(i,j,k) = 0.0
      enddo
      domore_k(k)=1

      do concurrent(j=js:je, I=is-1:ie)
      uhr(I,j,k) = uhtr(I,j,k)
      enddo
      do concurrent(J=js-1:je, i=is:ie)
      vhr(i,J,k) = vhtr(i,J,k)
      enddo
      if(.not. present(vol_prev)) then



      do concurrent (j=js:je, i=is:ie)
        hprev(i,j,k) = max(0.0, G%areaT(i,j)*h_end(i,j,k) +((uhr(I,j,k) &
     &- uhr(I-1,j,k)) +(vhr(i,J,k) - vhr(i,J-1,k))))



        hprev(i,j,k) = hprev(i,j,k) + max(0.0, 1.0e-13*hprev(i,j,k) - G%&
     &areaT(i,j)*h_end(i,j,k))
      enddo
      else
      do concurrent (j=js:je, i=is:ie)
        hprev(i,j,k) = vol_prev(i,j,k)
      enddo
      endif
      enddo

      do concurrent(j=jsd:jed, I=isd:ied-1)
      uh_neglect(I,j) = GV%H_subroundoff * MIN(G%areaT(i,j), G%areaT(i+1&
     &,j))
#line 260
      enddo
      do concurrent(J=jsd:jed-1, i=isd:ied)
      vh_neglect(i,J) = GV%H_subroundoff * MIN(G%areaT(i,j), G%areaT(i,j&
     &+1))
#line 263
      enddo



!$    do m=1,ntr
!$omp     target enter data map(to: Reg%Tr(m)%t)
!$    enddo


      if(flux_type_ctrl == 0) then
!$    do m=1,ntr
!$omp       target enter data map(alloc: Reg%Tr(m)%ad_x) if(associated(R&
!$omp&eg%Tr(m)%ad_x))
!$omp       target enter data map(alloc: Reg%Tr(m)%ad_y) if(associated(R&
!$omp&eg%Tr(m)%ad_y))
!$omp       target enter data map(alloc: Reg%Tr(m)%advection_xy) if(asso&
!$omp&ciated(Reg%Tr(m)%advection_xy))
!$omp       target enter data map(alloc: Reg%Tr(m)%ad2d_x) if(associated&
!$omp&(Reg%Tr(m)%ad2d_x))
!$omp       target enter data map(alloc: Reg%Tr(m)%ad2d_y) if(associated&
!$omp&(Reg%Tr(m)%ad2d_y))
!$    enddo
      do concurrent(m=1:ntr)

      advect_this_tracer(m) = .true.

      if (associated(Reg%Tr(m)%ad_x)) then
        do concurrent (k=1:nz, j=jsd:jed, I=IsdB:IedB)
          Reg%Tr(m)%ad_x(I,j,k) = 0.0
        enddo
      endif
      if (associated(Reg%Tr(m)%ad_y)) then
        do concurrent (k=1:nz, J=JsdB:jedB, i=isd:ied)
          Reg%Tr(m)%ad_y(i,J,k) = 0.0
        enddo
      endif
      if (associated(Reg%Tr(m)%advection_xy)) then
        do concurrent (k=1:nz, j=jsd:jed, i=isd:ied)
          Reg%Tr(m)%advection_xy(i,j,k) = 0.0
        enddo
      endif
      if (associated(Reg%Tr(m)%ad2d_x)) then
        do concurrent (j=jsd:jed, I=IsdB:IedB)
          Reg%Tr(m)%ad2d_x(I,j) = 0.0
        enddo
      endif
      if (associated(Reg%Tr(m)%ad2d_y)) then
        do concurrent (J=JsdB:JedB, i=isd:ied)
          Reg%Tr(m)%ad2d_y(i,J) = 0.0
        enddo
      endif
      enddo
      elseif(flux_type_ctrl == 1) then
!$    do m=1,ntr
!$omp       target enter data map(alloc: Reg%Tr(m)%ad_x_resolved) if(ass&
!$omp&ociated(Reg%Tr(m)%ad_x_resolved))
!$omp       target enter data map(alloc: Reg%Tr(m)%ad_y_resolved) if(ass&
!$omp&ociated(Reg%Tr(m)%ad_y_resolved))
!$    enddo
      do concurrent(m=1:ntr)
      if (associated(Reg%Tr(m)%ad_x_resolved)) then
        do concurrent (k=1:nz, j=jsd:jed, I=IsdB:IedB)
          Reg%Tr(m)%ad_x_resolved(I,j,k) = 0.0
        enddo
        advect_this_tracer(m) = .true.
      endif
      if (associated(Reg%Tr(m)%ad_y_resolved)) then
        do concurrent (k=1:nz, J=JsdB:jedB, i=isd:ied)
          Reg%Tr(m)%ad_y_resolved(i,J,k) = 0.0
        enddo
        advect_this_tracer(m) = .true.
      endif
      enddo
      elseif(flux_type_ctrl == 2) then
!$    do m=1,ntr
!$omp       target enter data map(alloc: Reg%Tr(m)%ad_x_param) if(associ&
!$omp&ated(Reg%Tr(m)%ad_x_param))
!$omp       target enter data map(alloc: Reg%Tr(m)%ad_y_param) if(associ&
!$omp&ated(Reg%Tr(m)%ad_y_param))
!$    enddo
      do concurrent(m=1:ntr)
      if (associated(Reg%Tr(m)%ad_x_param)) then
        do concurrent (k=1:nz, j=jsd:jed, I=IsdB:IedB)
          Reg%Tr(m)%ad_x_param(I,j,k) = 0.0
        enddo
        advect_this_tracer(m) = .true.
      endif
      if (associated(Reg%Tr(m)%ad_y_param)) then
        do concurrent (k=1:nz, J=JsdB:jedB, i=isd:ied)
          Reg%Tr(m)%ad_y_param(i,J,k) = 0.0
        enddo
        advect_this_tracer(m) = .true.
      endif
      enddo
      else
      call MOM_error(FATAL, "Inconsistent flux type in advect_tracer. Mu&
     &st be of 0 (residual), 1 (resolved), or 2 (parameterized)")
      endif

!$    if(associated(OBC)) then ; if(OBC%OBC_pe) then
!$omp     target update from(advect_this_tracer)
!$    endif ; endif

      isv = is ; iev = ie ; jsv = js ; jev = je
      nsten_halo = min(is - isd, ied - ie, js - jsd, jed - je) / stencil

      do itt=1,max_iter

      if(isv > is-stencil) then
      call do_group_pass(CS%pass_uhr_vhr_t_hprev, G%Domain, clock=id_clo&
     &ck_pass, omp_offload=.true.)
      isv = is - nsten_halo * stencil ; jsv = js - nsten_halo * stencil
      iev = ie + nsten_halo * stencil ; jev = je + nsten_halo * stencil


      if ((nsten_halo > 1) .or. (itt==1)) then
        do concurrent (k=1:nz, domore_k(k) > 0)
          do concurrent (j=jsv:jev, .not.domore_u(j,k))
            do i=isv+stencil-1,iev-stencil ; if (uhr(I,j,k) /= 0.0) then
              domore_u(j,k) = .true. ; exit
            endif ; enddo
          enddo
          do concurrent (J=jsv+stencil-1:jev-stencil, .not.domore_v(J,k)&
     &)
#line 386
            do i=isv+stencil,iev-stencil ; if (vhr(i,J,k) /= 0.0) then
              domore_v(J,k) = .true. ; exit
            endif ; enddo
          enddo



          domore_k_tmp = 0
          do concurrent (j=jsv:jev, domore_u(j,k)) reduce(max:domore_k_t&
     &mp)
#line 395
            domore_k_tmp = 1
          enddo
          do concurrent (J=jsv+stencil-1:jev-stencil, domore_v(J,k)) red&
     &uce(max:domore_k_tmp)
#line 398
            domore_k_tmp = 1
          enddo
          domore_k(k) = domore_k_tmp
        enddo
      endif
      endif


      isv = isv + stencil ; iev = iev - stencil
      jsv = jsv + stencil ; jev = jev - stencil







      if(x_first) then

      do ksb=1,nz,nkk
        keb = min(ksb + nkk - 1, nz)
        if (any(domore_k(ksb:keb) > 0)) then

          call advect_x(Reg%Tr, hprev, uhr, uh_neglect, OBC, domore_u, d&
     &omore_k, ntr, Idt, isv, iev, jsv-stencil, jev+stencil, ksb, keb, n&
     &kk, G, GV, US, flux_type_ctrl, advect_this_tracer, local_advect_sc&
     &heme)
#line 424
        endif
      enddo

      do ksb=1,nz,nkk
        keb = min(ksb + nkk - 1, nz)
        kke = keb - ksb + 1
        if (any(domore_k(ksb:keb) > 0)) then

          call advect_y(Reg%Tr, hprev, vhr, vh_neglect, OBC, domore_v, d&
     &omore_k, ntr, Idt, isv, iev, jsv, jev, ksb, keb, nkk, G, GV, US, f&
     &lux_type_ctrl, advect_this_tracer, local_advect_scheme)


          do concurrent (kk=1:kke, domore_k(ksb + kk - 1) > 0) local(dom&
     &ore_k_tmp, k)
#line 438
            k = ksb + kk - 1
            domore_k_tmp = 0
            do concurrent (j=jsv-stencil:jev+stencil, domore_u(j,k)) red&
     &uce(max:domore_k_tmp)
#line 441
              domore_k_tmp = 1
            enddo
            do concurrent (J=jsv-1:jev, domore_v(J,k)) reduce(max:domore&
     &_k_tmp)
#line 444
              domore_k_tmp = 1
            enddo
            domore_k(k) = domore_k_tmp
          enddo
        endif
      enddo
      else
      do ksb=1,nz,nkk
        keb = min(ksb + nkk - 1, nz)
        if (any(domore_k(ksb:keb) > 0)) then

          call advect_y(Reg%Tr, hprev, vhr, vh_neglect, OBC, domore_v, d&
     &omore_k, ntr, Idt, isv-stencil, iev+stencil, jsv, jev, ksb, keb, n&
     &kk, G, GV, US, flux_type_ctrl, advect_this_tracer, local_advect_sc&
     &heme)
#line 458
        endif
      enddo

      do ksb=1,nz,nkk
        keb = min(ksb + nkk - 1, nz)
        kke = keb - ksb + 1
        if (any(domore_k(ksb:keb) > 0)) then

          call advect_x(Reg%Tr, hprev, uhr, uh_neglect, OBC, domore_u, d&
     &omore_k, ntr, Idt, isv, iev, jsv, jev, ksb, keb, nkk, G, GV, US, f&
     &lux_type_ctrl, advect_this_tracer, local_advect_scheme)


          do concurrent (kk=1:kke, domore_k(ksb + kk - 1) > 0) local(dom&
     &ore_k_tmp, k)
#line 472
            k = ksb + kk - 1
            domore_k_tmp = 0
            do concurrent (j=jsv:jev, domore_u(j,k)) reduce(max:domore_k&
     &_tmp)
#line 475
              domore_k_tmp = 1
            enddo
            do concurrent (J=jsv-1:jev, domore_v(J,k)) reduce(max:domore&
     &_k_tmp)
#line 478
              domore_k_tmp = 1
            enddo
            domore_k(k) = domore_k_tmp
          enddo
        endif
      enddo

      endif


      if(itt >= max_iter) then
      exit
      endif


      if(isv > is-stencil) then
      do_any = 0
      call cpu_clock_begin(id_clock_sync)
      call sum_across_PEs(domore_k(:), nz)
      call cpu_clock_end(id_clock_sync)
      do k=1,nz ; do_any = do_any + domore_k(k) ; enddo
      if (do_any == 0) then
        exit
      endif

      endif

      enddo


!$    do m=1,ntr
!$omp     target exit data map(from: Reg%Tr(m)%t)
!$    enddo

      if(flux_type_ctrl == 0) then
!$    do m=1,ntr
!$omp       target exit data map(from: Reg%Tr(m)%ad_x) if(associated(Reg&
!$omp&%Tr(m)%ad_x))
!$omp       target exit data map(from: Reg%Tr(m)%ad_y) if(associated(Reg&
!$omp&%Tr(m)%ad_y))
!$omp       target exit data map(from: Reg%Tr(m)%advection_xy) if(associ&
!$omp&ated(Reg%Tr(m)%advection_xy))
!$omp       target exit data map(from: Reg%Tr(m)%ad2d_x) if(associated(R&
!$omp&eg%Tr(m)%ad2d_x))
!$omp       target exit data map(from: Reg%Tr(m)%ad2d_y) if(associated(R&
!$omp&eg%Tr(m)%ad2d_y))
!$    enddo
      elseif(flux_type_ctrl == 1) then
!$    do m=1,ntr
!$omp       target exit data map(from: Reg%Tr(m)%ad_x_resolved) if(assoc&
!$omp&iated(Reg%Tr(m)%ad_x_resolved))
!$omp       target exit data map(from: Reg%Tr(m)%ad_y_resolved) if(assoc&
!$omp&iated(Reg%Tr(m)%ad_y_resolved))
!$    enddo
      elseif(flux_type_ctrl == 2) then
!$    do m=1,ntr
!$omp       target exit data map(from: Reg%Tr(m)%ad_x_param) if(associat&
!$omp&ed(Reg%Tr(m)%ad_x_param))
!$omp       target exit data map(from: Reg%Tr(m)%ad_y_param) if(associat&
!$omp&ed(Reg%Tr(m)%ad_y_param))
!$    enddo
      endif

      if(present(uhr_out)) then
      do concurrent(k=1:nz, j=jsd:jed, i=isdB:iedB)
      uhr_out(i,j,k) = uhr(i,j,k)
      enddo
      endif
      if(present(vhr_out)) then
      do concurrent(k=1:nz, j=jsdB:jedB, i=isd:ied)
      vhr_out(i,j,k) = vhr(i,j,k)
      enddo
      endif
      if(present(vol_prev) .and. present(update_vol_prev)) then
      if(update_vol_prev) then
      do concurrent (k=1:nz, j=jsd:jed, i=isd:ied)
        vol_prev(i,j,k) = hprev(i,j,k)
      enddo
      endif
      endif

!$omp   target exit data map(release: hprev, uhr, vhr, uh_neglect, vh_ne&
!$omp&glect, domore_u, domore_v, local_advect_scheme, OBC, Reg, Reg%Tr(:&
!$omp&), advect_this_tracer)

      call cpu_clock_end(id_clock_advect)

      end subroutine advect_tracer




      subroutine advect_x(Tr, hprev, uhr, uh_neglect, OBC, domore_u, dom&
     &ore_k, ntr, Idt, is, ie, js, je, ksb, keb, nkk, G, GV, US, flux_ty&
     &pe, advect_this_tracer, advect_schemes)
      type(ocean_grid_type),                 intent(inout) :: G
      type(verticalGrid_type),               intent(in)    :: GV
      integer,                               intent(in)    :: ntr
      type(tracer_type), dimension(ntr),     intent(inout) :: Tr
      real, dimension(G%isd:G%ied,G%jsd:G%jed,GV%ke), intent(inout) :: h&
     &prev
      real, dimension(G%IsdB:G%IedB,G%jsd:G%jed,GV%ke), intent(inout) ::&
     & uhr
      real, dimension(G%IsdB:G%IedB,G%jsd:G%jed), intent(in) :: uh_negle&
     &ct
      type(ocean_OBC_type),                  pointer       :: OBC
      logical, dimension(G%jsd:G%jed,GV%ke), intent(inout) :: domore_u

      integer, dimension(GV%ke),             intent(in)    :: domore_k

      real,                                  intent(in)    :: Idt
      integer,                               intent(in)    :: is
      integer,                               intent(in)    :: ie
      integer,                               intent(in)    :: js
      integer,                               intent(in)    :: je
      integer,                               intent(in)    :: ksb
      integer,                               intent(in)    :: keb
      integer,                               intent(in)    :: nkk

      type(unit_scale_type),                 intent(in)    :: US
      integer,                               intent(in)    :: flux_type


      logical, dimension(ntr),               intent(in)    :: advect_thi&
     &s_tracer
#line 602
      integer, dimension(ntr),               intent(in)    :: advect_sch&
     &emes
      real, dimension(G%isd:G%ied,ntr) :: slope_x

      real, dimension(G%IsdB:G%IedB,G%jsd:G%jed,ntr,nkk) :: flux_x


      real, dimension(G%isd:G%ied,ntr) :: T_tmp


      real :: hup, hlos



      real :: uhh(G%IsdB:G%IedB)

      real, dimension(G%IsdB:G%IedB) :: hlst, Ihnew, CFL



      real :: min_h

      real :: tiny_h
      real :: h_neglect

      real :: aR, aL
      real :: dMx

      real :: dMn

      real :: Tp, Tc, Tm
      real :: dA
      real :: mA
      real :: a6
      logical :: do_i(G%isd:G%ied)
      logical :: usePLMslope, domore_u_jk
      integer :: i, j, k, kk, kke, m, n, i_up, stencil, ntr_id
      type(OBC_segment_type), pointer :: segment=>NULL()
      logical :: domore_u_initial(G%jsd:G%jed,nkk)


      kke = keb - ksb + 1

      usePLMslope = .false.

      stencil = 1
      do m = 1,ntr
      if((advect_schemes(m) == ADVECT_PLM) .or.(advect_schemes(m) == ADV&
     &ECT_PPM)) usePLMslope = .true.
      if(advect_schemes(m) == ADVECT_PPM) stencil = 2
      enddo

      min_h = 0.1*GV%Angstrom_H
      tiny_h = tiny(min_h)
      h_neglect = GV%H_subroundoff



!$omp   target enter data map(alloc: slope_x, T_tmp, uhh, CFL, hlst, Ihn&
!$omp&ew, do_i, flux_x, domore_u_initial)



      do concurrent(kk=1:kke, j=js:je) local(k)
      k = ksb + kk - 1
      domore_u_initial(j,kk) =(domore_k(k) > 0) .and. domore_u(j,k)
      enddo

!$omp   target teams loop collapse(2) private(slope_x, T_tmp, uhh, CFL, &
!$omp&hlst, Ihnew, Tp, dMx, dMn, m, i, n, ntr_id, hup, hlos, i_up, Tc, T&
!$omp&m, aL, aR, dA, mA, a6, domore_u_jk, k, do_i)
#line 672
      do kk=1,kke ; do j=js,je
      k = ksb + kk - 1
      if(domore_u_initial(j,kk)) then
      domore_u_jk = .false.


      if (usePLMslope) then
        do concurrent (m=1:ntr, i=is-stencil:ie+stencil, advect_this_tra&
     &cer(m))
#line 694
          Tp = Tr(m)%t(i+1,j,k) ; Tc = Tr(m)%t(i,j,k) ; Tm = Tr(m)%t(i-1&
     &,j,k)
#line 695
          dMx = max(Tp, Tc, Tm) - Tc
          dMn= Tc - min(Tp, Tc, Tm)
          slope_x(i,m) = G%mask2dCu(I,j) * G%mask2dCu(I-1,j) * sign(min(&
     &0.5*abs(Tp-Tm), 2.0*dMx, 2.0*dMn), Tp-Tm)
        enddo
      endif


      do concurrent (m=1:ntr, i=G%isd:G%ied, advect_this_tracer(m))
        T_tmp(i,m) = Tr(m)%t(i,j,k)
      enddo


      if (associated(OBC)) then ; if (OBC%OBC_pe) then
        do n=1,OBC%number_of_segments

          if (.not. associated(OBC%segment(n)%tr_Reg)) cycle
          if (OBC%segment(n)%is_E_or_W) then
            if (j >= OBC%segment(n)%HI%jsd .and. j <= OBC%segment(n)%HI%&
     &jed) then
              I = OBC%segment(n)%HI%IsdB
              do concurrent (m=1:OBC%segment(n)%tr_Reg%ntseg)
                ntr_id = OBC%segment(n)%tr_reg%Tr(m)%ntr_index
                if (advect_this_tracer(ntr_id)) then
                  if (OBC%segment(n)%direction == OBC_DIRECTION_W) then
                    T_tmp(i,ntr_id) = OBC%segment(n)%tr_Reg%Tr(m)%tres(i&
     &,j,k)
#line 721
                  else
                    T_tmp(i+1,ntr_id) = OBC%segment(n)%tr_Reg%Tr(m)%tres&
     &(i,j,k)
#line 723
                  endif
                endif
              enddo

              do concurrent (m=1:ntr, i=OBC%segment(n)%HI%IsdB-1:OBC%seg&
     &ment(n)%HI%IsdB+1, advect_this_tracer(m))
                Tp = T_tmp(i+1,m) ; Tc = T_tmp(i,m) ; Tm = T_tmp(i-1,m)
                dMx = max(Tp, Tc, Tm) - Tc
                dMn = Tc - min(Tp, Tc, Tm)
                slope_x(i,m) = G%mask2dCu(I,j) * G%mask2dCu(I-1,j) * sig&
     &n(min(0.5*abs(Tp-Tm), 2.0*dMx, 2.0*dMn), Tp-Tm)
              enddo
            endif
          endif
        enddo
      endif ; endif





      do concurrent (I=is-1:ie) reduce(.or.:domore_u_jk)
        if ((uhr(I,j,k) == 0.0) .or.((uhr(I,j,k) < 0.0) .and.(hprev(i+1,&
     &j,k) <= tiny_h)) .or.((uhr(I,j,k) > 0.0) .and.(hprev(i,j,k) <= tin&
     &y_h))) then
          uhh(I) = 0.0
          CFL(I) = 0.0
        elseif (uhr(I,j,k) < 0.0) then
          hup = hprev(i+1,j,k) - G%areaT(i+1,j)*min_h
          hlos = MAX(0.0, uhr(I+1,j,k))
          if ((((hup - hlos) + uhr(I,j,k)) < 0.0) .and.((0.5*hup + uhr(I&
     &,j,k)) < 0.0)) then
            uhh(I) = MIN(-0.5*hup, -hup+hlos, 0.0)
            domore_u_jk = .true.
          else
            uhh(I) = uhr(I,j,k)
          endif
          CFL(I) = - uhh(I) / (hprev(i+1,j,k))
        else
          hup = hprev(i,j,k) - G%areaT(i,j)*min_h
          hlos = MAX(0.0, -uhr(I-1,j,k))
          if ((((hup - hlos) - uhr(I,j,k)) < 0.0) .and.((0.5*hup - uhr(I&
     &,j,k)) < 0.0)) then
            uhh(I) = MAX(0.5*hup, hup-hlos, 0.0)
            domore_u_jk = .true.
          else
            uhh(I) = uhr(I,j,k)
          endif
          CFL(I) = uhh(I) / (hprev(i,j,k))
        endif
      enddo

      domore_u(j,k) = domore_u_jk

      do concurrent (m=1:ntr, advect_this_tracer(m))
        if (advect_schemes(m) == ADVECT_PPM .or. advect_schemes(m) == AD&
     &VECT_PPMH3) then
#line 779
          do concurrent (I=is-1:ie)

            if (uhh(I) >= 0.0) then
              i_up = i
            else
              i_up = i+1
            endif


            Tp = T_tmp(i_up+1,m) ; Tc = T_tmp(i_up,m) ; Tm = T_tmp(i_up-&
     &1,m)
            if (advect_schemes(m) == ADVECT_PPMH3) then
              aL = ( 5.*Tc + ( 2.*Tm - Tp ) )/6.
              aL = max( min(Tc,Tm), aL) ; aL = min( max(Tc,Tm), aL)
              aR = ( 5.*Tc + ( 2.*Tp - Tm ) )/6.
              aR = max( min(Tc,Tp), aR) ; aR = min( max(Tc,Tp), aR)
            else
              aL = 0.5 * ((Tm + Tc) + (slope_x(i_up-1,m) - slope_x(i_up,&
     &m)) / 3.)
#line 797
              aR = 0.5 * ((Tc + Tp) + (slope_x(i_up,m) - slope_x(i_up+1,&
     &m)) / 3.)
#line 798
            endif

            dA = aR - aL ; mA = 0.5*( aR + aL )
            if (G%mask2dCu(I_up,j)*G%mask2dCu(I_up-1,j)*(Tp-Tc)*(Tc-Tm) &
     &<= 0.) then
#line 802
              aL = Tc ; aR = Tc
            elseif ( dA*(Tc-mA) > (dA*dA)/6. ) then
              aL = (3.*Tc) - 2.*aR
            elseif ( dA*(Tc-mA) < - (dA*dA)/6. ) then
              aR = (3.*Tc) - 2.*aL
            endif

            a6 = 6.*Tc - 3. * (aR + aL)

            if (uhh(I) >= 0.0) then
              flux_x(I,j,m,kk) = uhh(I)*( aR - 0.5 * CFL(I) * ((aR - aL)&
     & - a6 *(1. - 2./3. * CFL(I))))
            else
              flux_x(I,j,m,kk) = uhh(I)*( aL + 0.5 * CFL(I) * ((aR - aL)&
     & + a6 *(1. - 2./3. * CFL(I))))
            endif
          enddo
        else
          do concurrent (I=is-1:ie)
            if (uhh(I) >= 0.0) then





              Tc = T_tmp(i,m)
              flux_x(I,j,m,kk) = uhh(I)*( Tc + 0.5 * slope_x(i,m) * ( 1.&
     & - CFL(I)))
#line 829
            else





              Tc = T_tmp(i+1,m)
              flux_x(I,j,m,kk) = uhh(I)*( Tc - 0.5 * slope_x(i+1,m) * (1&
     &. - CFL(I)))
#line 837
            endif
          enddo
        endif
      enddo

      if (associated(OBC)) then ; if (OBC%OBC_pe) then
        if (OBC%specified_u_BCs_exist_globally .or. OBC%open_u_BCs_exist&
     &_globally) then
#line 844
          do n=1,OBC%number_of_segments

            if (.not. associated(OBC%segment(n)%tr_Reg)) cycle
            if (OBC%segment(n)%is_E_or_W) then
              if (j>=OBC%segment(n)%HI%jsd .and. j<=OBC%segment(n)%HI%je&
     &d) then
#line 849
                I = OBC%segment(n)%HI%IsdB


                if ((uhr(I,j,k) > 0.0) .and. (OBC%segment(n)%direction =&
     &= OBC_DIRECTION_W) .or.(uhr(I,j,k) < 0.0) .and.(OBC%segment(n)%dir&
     &ection == OBC_DIRECTION_E)) then
#line 854
                  uhh(I) = uhr(I,j,k)

                  do concurrent (m=1:OBC%segment(n)%tr_Reg%ntseg)
                    ntr_id = OBC%segment(n)%tr_reg%Tr(m)%ntr_index
                    if (advect_this_tracer(ntr_id)) then
                      flux_x(I,j,ntr_id,kk) = uhh(I) * OBC%segment(n)%tr&
     &_Reg%Tr(m)%tres(I,j,k)
                    endif
                  enddo
                endif
              endif
            endif
          enddo
        endif

        if (OBC%open_u_BCs_exist_globally) then
          do n=1,OBC%number_of_segments

            I = OBC%segment(n)%HI%IsdB
            if (OBC%segment(n)%is_E_or_W .and. (j >= OBC%segment(n)%HI%j&
     &sd .and. j<= OBC%segment(n)%HI%jed)) then
#line 874
              if (OBC%segment(n)%specified) cycle
              if (.not. associated(OBC%segment(n)%tr_Reg)) cycle


              if ((uhr(I,j,k) > 0.0) .and. (G%mask2dT(i,j) < 0.5) .or.(u&
     &hr(I,j,k) < 0.0) .and.(G%mask2dT(i+1,j) < 0.5)) then
                uhh(I) = uhr(I,j,k)
                do concurrent (m=1:OBC%segment(n)%tr_Reg%ntseg)
                  ntr_id = OBC%segment(n)%tr_reg%Tr(m)%ntr_index
                  if (advect_this_tracer(ntr_id)) then
                    flux_x(I,j,ntr_id,kk) = uhh(I) * OBC%segment(n)%tr_R&
     &eg%Tr(m)%tres(I,j,k)
                  endif
                enddo
              endif
            endif
          enddo
        endif
      endif ; endif



      do concurrent (I=is-1:ie)
        uhr(I,j,k) = uhr(I,j,k) - uhh(I)
        if (abs(uhr(I,j,k)) < uh_neglect(I,j)) uhr(I,j,k) = 0.0
      enddo
      do concurrent (i=is:ie)
        if ((uhh(I) /= 0.0) .or. (uhh(I-1) /= 0.0)) then
          do_i(i) = .true.
          hlst(i) = hprev(i,j,k)
          hprev(i,j,k) = hprev(i,j,k) - (uhh(I) - uhh(I-1))
          if (hprev(i,j,k) <= 0.0) then ; do_i(i) = .false.
          elseif (hprev(i,j,k) < h_neglect*G%areaT(i,j)) then
            hlst(i) = hlst(i) + (h_neglect*G%areaT(i,j) - hprev(i,j,k))
            Ihnew(i) = 1.0 / (h_neglect*G%areaT(i,j))
          else ;  Ihnew(i) = 1.0 / hprev(i,j,k) ; endif
        else
          do_i(i) = .false.
        endif
      enddo


      if (associated(OBC)) then
        if (.not.OBC%exterior_OBC_bug .and. OBC%OBC_pe .and.(OBC%specifi&
     &ed_u_BCs_exist_globally .or. OBC%open_u_BCs_exist_globally)) then

          do concurrent (i=is:ie, OBC%segnum_u(I-1,j) > 0 .or. OBC%segnu&
     &m_u(I,j) < 0)
#line 921
            do_i(i) = .false.
          enddo
        endif
      endif


      do concurrent (m=1:ntr, advect_this_tracer(m))

        if (flux_type == 0) then
          do concurrent (i=is:ie)
            if (do_i(i)) then
              if (Ihnew(i) > 0.0) then
                Tr(m)%t(i,j,k) = (Tr(m)%t(i,j,k) * hlst(i) -(flux_x(I,j,&
     &m,kk) - flux_x(I-1,j,m,kk))) * Ihnew(i)
              endif
            endif
          enddo
        endif


        if (flux_type == 0) then
          if (associated(Tr(m)%ad_x)) then
            do concurrent (I=is-1:ie)
              Tr(m)%ad_x(I,j,k) = Tr(m)%ad_x(I,j,k) + flux_x(I,j,m,kk) *&
     & Idt
#line 945
            enddo
          endif



          if (associated(Tr(m)%advection_xy)) then
            do concurrent (i=is:ie, do_i(i))
              Tr(m)%advection_xy(i,j,k) = Tr(m)%advection_xy(i,j,k) -(fl&
     &ux_x(I,j,m,kk) - flux_x(I-1,j,m,kk)) * Idt * G%IareaT(i,j)
            enddo
          endif
        elseif (flux_type == 1) then
          if (associated(Tr(m)%ad_x_resolved)) then
            do concurrent (I=is-1:ie)
              Tr(m)%ad_x_resolved(I,j,k) = Tr(m)%ad_x_resolved(I,j,k) + &
     &flux_x(I,j,m,kk) * Idt
            enddo
          endif
        elseif (flux_type == 2) then
          if (associated(Tr(m)%ad_x_param)) then
            do concurrent (I=is-1:ie)
              Tr(m)%ad_x_param(I,j,k) = Tr(m)%ad_x_param(I,j,k) + flux_x&
     &(I,j,m,kk)*Idt
#line 967
            enddo
          endif
        endif
      enddo
      endif
      enddo ; enddo


      if(flux_type == 0) then

      do concurrent(m=1:ntr, kk=1:kke,(domore_k(ksb + kk - 1) > 0) .and.&
     &(Tr(m)%conc_underflow > 0.0)) local(k)
      k = ksb + kk - 1
      do concurrent (j=js:je, i=is:ie)
        if (abs(Tr(m)%t(i,j,k)) < Tr(m)%conc_underflow) Tr(m)%t(i,j,k) =&
     & 0.0
#line 982
      enddo
      enddo
      endif

      if(flux_type == 0) then
      do m=1,ntr ; if(associated(Tr(m)%ad2d_x)) then

      do concurrent (j=js:je, I=is-1:ie) local(kk)
        do kk=1,kke
          if (domore_u_initial(j,kk)) Tr(m)%ad2d_x(I,j) = Tr(m)%ad2d_x(I&
     &,j) + flux_x(I,j,m,kk) * Idt
        enddo
      enddo
      endif ; enddo
      endif

!$omp   target exit data map(release: slope_x, T_tmp, uhh, CFL, hlst, Ih&
!$omp&new, do_i, flux_x, domore_u_initial)
      end subroutine advect_x



      subroutine advect_y(Tr, hprev, vhr, vh_neglect, OBC, domore_v, dom&
     &ore_k, ntr, Idt, is, ie, js, je, ksb, keb, nkk, G, GV, US, flux_ty&
     &pe, advect_this_tracer, advect_schemes)
      type(ocean_grid_type),                 intent(inout) :: G
      type(verticalGrid_type),               intent(in)    :: GV
      integer,                               intent(in)    :: ntr
      type(tracer_type), dimension(ntr),     intent(inout) :: Tr
      real, dimension(G%isd:G%ied,G%jsd:G%jed,GV%ke), intent(inout) :: h&
     &prev
      real, dimension(G%isd:G%ied,G%JsdB:G%JedB,GV%ke), intent(inout) ::&
     & vhr
      real, dimension(G%isd:G%ied,G%JsdB:G%JedB), intent(inout) :: vh_ne&
     &glect
      type(ocean_OBC_type),                  pointer       :: OBC
      logical, dimension(G%JsdB:G%JedB,GV%ke), intent(inout) :: domore_v

      integer, dimension(GV%ke),             intent(in)    :: domore_k

      real,                                  intent(in)    :: Idt
      integer,                               intent(in)    :: is
      integer,                               intent(in)    :: ie
      integer,                               intent(in)    :: js
      integer,                               intent(in)    :: je
      integer,                               intent(in)    :: ksb
      integer,                               intent(in)    :: keb
      integer,                               intent(in)    :: nkk

      type(unit_scale_type),                 intent(in)    :: US
      integer,                               intent(in)    :: flux_type


      logical, dimension(ntr),               intent(in)    :: advect_thi&
     &s_tracer
#line 1036
      integer, dimension(ntr),               intent(in)    :: advect_sch&
     &emes
      real, dimension(G%isd:G%ied,ntr,G%jsd:G%jed,nkk) :: slope_y

      real, dimension(G%isd:G%ied,ntr,G%JsdB:G%JedB,nkk) :: flux_y


      real, dimension(G%isd:G%ied,ntr,G%JsdB:G%JedB,nkk) :: T_tmp

      real :: vhh(G%isd:G%ied,G%JsdB:G%JedB,nkk)

      real :: hup, hlos



      real, dimension(G%IsdB:G%IedB) :: hlst, Ihnew, CFL



      real :: min_h

      real :: tiny_h
      real :: h_neglect

      real :: aR, aL
      real :: dMx

      real :: dMn

      real :: Tp, Tc, Tm
      real :: dA
      real :: mA
      real :: a6
      logical :: do_j_tr(G%jsd:G%jed,nkk)
      logical :: do_i(G%isd:G%ied)
      logical :: usePLMslope
      integer :: i, j, j2, k, kk, kke, m, n, j_up, stencil, ntr_id
      type(OBC_segment_type), pointer :: segment=>NULL()
      logical :: domore_v_initial(G%JsdB:G%JedB,nkk)
      logical :: domore_v_jk

      kke = keb - ksb + 1

      usePLMslope = .false.

      stencil = 1
      do m = 1,ntr
      if((advect_schemes(m) == ADVECT_PLM) .or.(advect_schemes(m) == ADV&
     &ECT_PPM)) usePLMslope = .true.
      if(advect_schemes(m) == ADVECT_PPM) stencil = 2
      enddo

      min_h = 0.1*GV%Angstrom_H
      tiny_h = tiny(min_h)
      h_neglect = GV%H_subroundoff

!$omp   target enter data map(alloc: vhh, T_tmp, slope_y, flux_y, domore&
!$omp&_v_initial, do_j_tr, do_i)










      do concurrent(kk=1:kke, j=G%jsd:G%jed) local(k)
      k = ksb + kk - 1
      do_j_tr(j,kk) = .false.
      enddo
      do concurrent(kk=1:kke, J=js-1:je,(domore_k(ksb + kk - 1) > 0) .an&
     &d. domore_v(J,ksb + kk - 1)) local(k)
#line 1109
      k = ksb + kk - 1
      do concurrent(j2=1-stencil:stencil)
      do_j_tr(j+j2,kk) = .true.
      enddo
      enddo

      do concurrent(kk=1:kke, j=G%JsdB:G%JedB) local(k)
      k = ksb + kk - 1
      domore_v_initial(j,kk) =(domore_k(k) > 0) .and. domore_v(j,k)
      enddo



      if(usePLMslope) then
      do concurrent(kk=1:kke, j=js-stencil:je+stencil, do_j_tr(j,kk))
      do concurrent (m=1:ntr, i=is:ie, advect_this_tracer(m)) local(k)
        k = ksb + kk - 1
#line 1140
        Tp = Tr(m)%t(i,j+1,k) ; Tc = Tr(m)%t(i,j,k) ; Tm = Tr(m)%t(i,j-1&
     &,k)
#line 1141
        dMx = max(Tp, Tc, Tm) - Tc
        dMn = Tc - min(Tp, Tc, Tm)
        slope_y(i,m,j,kk) = G%mask2dCv(i,J) * G%mask2dCv(i,J-1) * sign(m&
     &in(0.5*abs(Tp-Tm), 2.0*dMx, 2.0*dMn), Tp-Tm)
      enddo
      enddo
      endif



      do concurrent(kk=1:kke, j=G%jsd:G%jed, m=1:ntr, i=G%isd:G%ied,(dom&
     &ore_k(ksb + kk - 1) > 0) .and. advect_this_tracer(m)) local(k)
      k = ksb + kk - 1
      T_tmp(i,m,j,kk) = Tr(m)%t(i,j,k)
      enddo


      if(associated(OBC)) then ; if(OBC%OBC_pe) then
      do kk=1,kke ; if(domore_k(ksb + kk - 1) > 0) then
      k = ksb + kk - 1
      do n=1,OBC%number_of_segments

        if (.not. associated(OBC%segment(n)%tr_Reg)) cycle
        do i=is,ie
          if (OBC%segment(n)%is_N_or_S) then
            if (i>=OBC%segment(n)%HI%isd .and. i<=OBC%segment(n)%HI%ied)&
     & then
#line 1167
              J = OBC%segment(n)%HI%JsdB
              do m = 1,OBC%segment(n)%tr_Reg%ntseg
                ntr_id = OBC%segment(n)%tr_reg%Tr(m)%ntr_index
                if (advect_this_tracer(ntr_id)) then
                  if (OBC%segment(n)%direction == OBC_DIRECTION_S) then
                    T_tmp(i,ntr_id,j,kk) = OBC%segment(n)%tr_Reg%Tr(m)%t&
     &res(i,j,k)
#line 1173
                  else
                    T_tmp(i,ntr_id,j+1,kk) = OBC%segment(n)%tr_Reg%Tr(m)&
     &%tres(i,j,k)
#line 1175
                  endif
                endif
              enddo
              do m = 1,ntr
                if (advect_this_tracer(m)) then
                  do j=OBC%segment(n)%HI%JsdB-1,OBC%segment(n)%HI%JsdB+1
                    Tp = T_tmp(i,m,j+1,kk) ; Tc = T_tmp(i,m,j,kk) ; Tm =&
     & T_tmp(i,m,j-1,kk)
#line 1182
                    dMx = max( Tp, Tc, Tm ) - Tc
                    dMn= Tc - min( Tp, Tc, Tm )
                    slope_y(i,m,j,kk) = G%mask2dCv(i,J)*G%mask2dCv(i,J-1&
     &) * sign(min(0.5*abs(Tp-Tm), 2.0*dMx, 2.0*dMn), Tp-Tm)
                  enddo
                endif
              enddo
            endif
          endif
        enddo
      enddo
      endif ; enddo
      endif ; endif





!$omp   target teams loop collapse(2) private(CFL, Ihnew, hup, hlos, j_u&
!$omp&p, Tp, Tc, Tm, i, m, aL, aR, dA, mA, a6, n, ntr_id, domore_v_jk, k&
!$omp&)
      do kk=1,kke ; do J=js-1,je
      k = ksb + kk - 1
      if(domore_v_initial(J,kk)) then
      domore_v_jk = .false.

      do concurrent (i=is:ie) reduce(.or.:domore_v_jk)
        if ((vhr(i,J,k) == 0.0) .or.((vhr(i,J,k) < 0.0) .and.(hprev(i,j+&
     &1,k) <= tiny_h)) .or.((vhr(i,J,k) > 0.0) .and.(hprev(i,j,k) <= tin&
     &y_h))) then
          vhh(i,J,kk) = 0.0
          CFL(i) = 0.0
        elseif (vhr(i,J,k) < 0.0) then
          hup = hprev(i,j+1,k) - G%areaT(i,j+1)*min_h
          hlos = MAX(0.0, vhr(i,J+1,k))
          if ((((hup - hlos) + vhr(i,J,k)) < 0.0) .and.((0.5*hup + vhr(i&
     &,J,k)) < 0.0)) then
            vhh(i,J,kk) = MIN(-0.5*hup, -hup+hlos, 0.0)
            domore_v_jk = .true.
          else
            vhh(i,J,kk) = vhr(i,J,k)
          endif
          CFL(i) = - vhh(i,J,kk) / hprev(i,j+1,k)
        else
          hup = hprev(i,j,k) - G%areaT(i,j)*min_h
          hlos = MAX(0.0, -vhr(i,J-1,k))
          if ((((hup - hlos) - vhr(i,J,k)) < 0.0) .and.((0.5*hup - vhr(i&
     &,J,k)) < 0.0)) then
            vhh(i,J,kk) = MAX(0.5*hup, hup-hlos, 0.0)
            domore_v_jk = .true.
          else
            vhh(i,J,kk) = vhr(i,J,k)
          endif
          CFL(i) = vhh(i,J,kk) / hprev(i,j,k)
        endif
      enddo

      domore_v(j,k) = domore_v_jk

      do concurrent (m=1:ntr, advect_this_tracer(m))
        if (advect_schemes(m) == ADVECT_PPM .or. advect_schemes(m) == AD&
     &VECT_PPMH3) then
#line 1243
          do concurrent (i=is:ie)

            if (vhh(i,J,kk) >= 0.0) then
              j_up = j
            else
              j_up = j + 1
            endif


            Tp = T_tmp(i,m,j_up+1,kk) ; Tc = T_tmp(i,m,j_up,kk) ; Tm = T&
     &_tmp(i,m,j_up-1,kk)
            if (advect_schemes(m) == ADVECT_PPMH3) then
              aL = ( 5.*Tc + ( 2.*Tm - Tp ) )/6.
              aL = max( min(Tc,Tm), aL) ; aL = min( max(Tc,Tm), aL)
              aR = ( 5.*Tc + ( 2.*Tp - Tm ) )/6.
              aR = max( min(Tc,Tp), aR) ; aR = min( max(Tc,Tp), aR)
            else
              aL = 0.5 * ((Tm + Tc) + (slope_y(i,m,j_up-1,kk) - slope_y(&
     &i,m,j_up,kk)) / 3.)
#line 1261
              aR = 0.5 * ((Tc + Tp) + (slope_y(i,m,j_up,kk) - slope_y(i,&
     &m,j_up+1,kk)) / 3.)
#line 1262
            endif

            dA = aR - aL ; mA = 0.5*( aR + aL )
            if (G%mask2dCv(i,J_up)*G%mask2dCv(i,J_up-1)*(Tp-Tc)*(Tc-Tm) &
     &<= 0.) then
#line 1266
              aL = Tc ; aR = Tc
            elseif ( dA*(Tc-mA) > (dA*dA)/6. ) then
              aL = (3.*Tc) - 2.*aR
            elseif ( dA*(Tc-mA) < - (dA*dA)/6. ) then
              aR = (3.*Tc) - 2.*aL
            endif

            a6 = 6.*Tc - 3. * (aR + aL)

            if (vhh(i,J,kk) >= 0.0) then
              flux_y(i,m,J,kk) = vhh(i,J,kk)*( aR - 0.5 * CFL(i) * ((aR &
     &- aL) - a6 *(1. - 2./3. * CFL(I))))
            else
              flux_y(i,m,J,kk) = vhh(i,J,kk)*( aL + 0.5 * CFL(i) * ((aR &
     &- aL) + a6 *(1. - 2./3. * CFL(I))))
            endif
          enddo
        else
          do concurrent (i=is:ie)
            if (vhh(i,J,kk) >= 0.0) then





              Tc = T_tmp(i,m,j,kk)
              flux_y(i,m,J,kk) = vhh(i,J,kk)*( Tc + 0.5 * slope_y(i,m,j,&
     &kk) *(1. - CFL(i)))
#line 1293
            else





              Tc = T_tmp(i,m,j+1,kk)
              flux_y(i,m,J,kk) = vhh(i,J,kk)*( Tc - 0.5 * slope_y(i,m,j+&
     &1,kk) *(1. - CFL(i)))
#line 1301
            endif
          enddo
        endif
      enddo

      if (associated(OBC)) then ; if (OBC%OBC_pe) then
        if (OBC%specified_v_BCs_exist_globally .or. OBC%open_v_BCs_exist&
     &_globally) then
#line 1308
          do n=1,OBC%number_of_segments
            if (.not. OBC%segment(n)%specified) cycle
            if (.not. associated(OBC%segment(n)%tr_Reg)) cycle
            if (OBC%segment(n)%is_N_or_S) then
              if (J >= OBC%segment(n)%HI%JsdB .and. J<= OBC%segment(n)%H&
     &I%JedB) then
#line 1313
                do i=OBC%segment(n)%HI%isd,OBC%segment(n)%HI%ied


                  if ((vhr(i,J,k) > 0.0) .and. (OBC%segment(n)%direction&
     & == OBC_DIRECTION_S) .or.(vhr(i,J,k) < 0.0) .and.(OBC%segment(n)%d&
     &irection == OBC_DIRECTION_N)) then
#line 1318
                    vhh(i,J,kk) = vhr(i,J,k)
                    do m=1,OBC%segment(n)%tr_Reg%ntseg
                      ntr_id = OBC%segment(n)%tr_reg%Tr(m)%ntr_index
                      if (advect_this_tracer(ntr_id)) then
                        flux_y(i,ntr_id,J,kk) = vhh(i,J,kk)*OBC%segment(&
     &n)%tr_Reg%Tr(m)%tres(i,J,k)
#line 1323
                      endif
                    enddo
                  endif
                enddo
              endif
            endif
          enddo
        endif

        if (OBC%open_v_BCs_exist_globally) then
          do n=1,OBC%number_of_segments
            if (OBC%segment(n)%specified) cycle
            if (.not. associated(OBC%segment(n)%tr_Reg)) cycle
            if (OBC%segment(n)%is_N_or_S .and. (J >= OBC%segment(n)%HI%J&
     &sdB .and. J<= OBC%segment(n)%HI%JedB)) then
#line 1337
              do i=OBC%segment(n)%HI%isd,OBC%segment(n)%HI%ied

                if ((vhr(i,J,k) > 0.0) .and. (G%mask2dT(i,j) < 0.5) .or.&
     &(vhr(i,J,k) < 0.0) .and.(G%mask2dT(i,j+1) < 0.5)) then
                  vhh(i,J,kk) = vhr(i,J,k)
                  do m=1,OBC%segment(n)%tr_Reg%ntseg
                    ntr_id = OBC%segment(n)%tr_reg%Tr(m)%ntr_index
                    if (advect_this_tracer(ntr_id)) then
                      flux_y(i,ntr_id,J,kk) = vhh(i,J,kk) * OBC%segment(&
     &n)%tr_Reg%Tr(m)%tres(i,J,k)
                    endif
                  enddo
                endif
              enddo
            endif
          enddo
        endif
      endif ; endif

      else
      do concurrent (i=is:ie)
        vhh(i,J,kk) = 0.0
      enddo
      do concurrent (m=1:ntr, i=is:ie, advect_this_tracer(m))
        flux_y(i,m,J,kk) = 0.0
      enddo
      endif
      enddo ; enddo

      do concurrent(kk=1:kke, J=js-1:je, i=is:ie, domore_k(ksb + kk - 1)&
     & > 0) local(k)
#line 1367
      k = ksb + kk - 1
      vhr(i,J,k) = vhr(i,J,k) - vhh(i,J,kk)
      if(abs(vhr(i,J,k)) < vh_neglect(i,J)) vhr(i,J,k) = 0.0
      enddo



!$omp   target teams loop collapse(2) private(hlst, Ihnew, i, m, k, do_i&
!$omp&)
#line 1375
      do kk=1,kke ; do j=js,je
      k = ksb + kk - 1
      if(do_j_tr(j,kk)) then
      do concurrent (i=is:ie)
        if ((vhh(i,J,kk) /= 0.0) .or. (vhh(i,J-1,kk) /= 0.0)) then
          do_i(i) = .true.
          hlst(i) = hprev(i,j,k)
          hprev(i,j,k) = max(hprev(i,j,k) - (vhh(i,J,kk) - vhh(i,J-1,kk)&
     &), 0.0)
#line 1383
          if (hprev(i,j,k) <= 0.0) then ; do_i(i) = .false.
          elseif (hprev(i,j,k) < h_neglect*G%areaT(i,j)) then
            hlst(i) = hlst(i) + (h_neglect*G%areaT(i,j) - hprev(i,j,k))
            Ihnew(i) = 1.0 / (h_neglect*G%areaT(i,j))
          else ;  Ihnew(i) = 1.0 / hprev(i,j,k) ; endif
        else ; do_i(i) = .false. ; endif
      enddo


      if (associated(OBC)) then
        if (.not.OBC%exterior_OBC_bug .and. OBC%OBC_pe .and.(OBC%specifi&
     &ed_v_BCs_exist_globally .or. OBC%open_v_BCs_exist_globally)) then

          do concurrent (i=is:ie, OBC%segnum_v(i,J-1) > 0 .or. OBC%segnu&
     &m_v(i,J) < 0)
#line 1397
            do_i(i) = .false.
          enddo
        endif
      endif


      do concurrent (m=1:ntr, advect_this_tracer(m))
        if (flux_type == 0) then
          do concurrent (i=is:ie, do_i(i))
            Tr(m)%t(i,j,k) = (Tr(m)%t(i,j,k) * hlst(i) -(flux_y(i,m,J,kk&
     &) - flux_y(i,m,J-1,kk))) * Ihnew(i)
          enddo



          if (associated(Tr(m)%advection_xy)) then
            do concurrent (i=is:ie, do_i(i))
              Tr(m)%advection_xy(i,j,k) = Tr(m)%advection_xy(i,j,k) -(fl&
     &ux_y(i,m,J,kk) - flux_y(i,m,J-1,kk))* Idt * G%IareaT(i,j)
            enddo
          endif
        endif
      enddo
      endif
      enddo ; enddo


      if(flux_type == 0) then
      do concurrent(kk=1:kke, m=1:ntr,(domore_k(ksb + kk - 1) > 0) .and.&
     &(Tr(m)%conc_underflow > 0.0)) local(k)
      k = ksb + kk - 1
      do concurrent (j=js:je, i=is:ie, abs(Tr(m)%t(i,j,k)) < Tr(m)%conc_&
     &underflow)
#line 1429
        Tr(m)%t(i,j,k) = 0.0
      enddo
      enddo
      endif

      if(flux_type == 0) then
      do m=1,ntr ; if(associated(Tr(m)%ad_y)) then
      do concurrent (kk=1:kke, J=js-1:je, i=is:ie, domore_v_initial(J,kk&
     &)) local(k)
#line 1437
        k = ksb + kk - 1
        Tr(m)%ad_y(i,J,k) = Tr(m)%ad_y(i,J,k) + flux_y(i,m,J,kk)*Idt
      enddo
      endif ; enddo

      do m=1,ntr ; if(associated(Tr(m)%ad2d_y)) then

      do concurrent (J=js-1:je, i=is:ie) local(kk)
        do kk=1,kke
          if (domore_v_initial(J,kk)) Tr(m)%ad2d_y(i,J) = Tr(m)%ad2d_y(i&
     &,J) + flux_y(i,m,J,kk)*Idt
        enddo
      enddo
      endif ; enddo
      elseif(flux_type == 1) then
      do m=1,ntr ; if(associated(Tr(m)%ad_y_resolved)) then
      do concurrent (kk=1:kke, J=js-1:je, i=is:ie, domore_v_initial(J,kk&
     &)) local(k)
#line 1454
        k = ksb + kk - 1
        Tr(m)%ad_y_resolved(i,J,k) = Tr(m)%ad_y_resolved(i,J,k) + flux_y&
     &(i,m,J,kk)*Idt
#line 1456
      enddo
      endif ; enddo
      elseif(flux_type == 2) then
      do m=1,ntr ; if(associated(Tr(m)%ad_y_param)) then
      do concurrent (kk=1:kke, J=js-1:je, i=is:ie, domore_v_initial(J,kk&
     &)) local(k)
#line 1461
        k = ksb + kk - 1
        Tr(m)%ad_y_param(i,J,k) = Tr(m)%ad_y_param(i,J,k) + flux_y(i,m,J&
     &,kk)*Idt
#line 1463
      enddo
      endif ; enddo
      endif

!$omp   target exit data map(release: vhh, T_tmp, slope_y, flux_y, domor&
!$omp&e_v_initial, do_j_tr, do_i)
#line 1468
      end subroutine advect_y


      subroutine tracer_advect_init(Time, G, US, param_file, diag, CS)
      type(time_type), target, intent(in) :: Time
      type(ocean_grid_type), intent(in)  :: G
      type(unit_scale_type), intent(in)  :: US
      type(param_file_type), intent(in)  :: param_file
      type(diag_ctrl), target, intent(inout) :: diag
      type(tracer_advect_CS), pointer    :: CS
#line "/lustre/orion/csc693/scratch/jg4/mom/MOM6-examples/src/MOM6/src/framework/version_variable.h" 8
      character(len=*), parameter :: version = 'unknown'
#line "/lustre/orion/csc693/scratch/jg4/mom/MOM6-examples/src/MOM6/src/tracer/MOM_tracer_advect.F90" 1481
      character(len=40) :: mdl = "MOM_tracer_advect"
      character(len=256) :: mesg



      integer, parameter :: default_nkblock = 1


      if(associated(CS)) then
      call MOM_error(WARNING, "tracer_advect_init called with associated&
     & control structure.")
#line 1491
      return
      endif
      allocate(CS)

      CS%diag => diag


      call log_version(param_file, mdl, version, "")
      call get_param(param_file, mdl, "DT", CS%dt, fail_if_missing=.true&
     &., desc="The (baroclinic) dynamics time step.", units="s", scale=U&
     &S%s_to_T)
#line 1501
      call get_param(param_file, mdl, "DEBUG", CS%debug, default=.false.&
     &)
#line 1502
      call get_param(param_file, mdl, "TRACER_ADVECT_NKBLOCK", CS%nkbloc&
     &k, desc="The k-direction block size used in tracer advection calcu&
     &lations. "// "The default 0 setting dynamically uses the full vert&
     &ical column.", default=default_nkblock, layoutParam=.true.)
      if(CS%nkblock < 0) call MOM_error(FATAL, "MOM_tracer_advect, trace&
     &r_advect_init: "// "TRACER_ADVECT_NKBLOCK must be nonnegative; use&
     & 0 to select the full vertical column.")
#line 1508
      call get_param(param_file, mdl, "TRACER_ADVECTION_SCHEME", mesg, d&
     &esc="The horizontal transport scheme for tracers:\n"// trim(Tracer&
     &AdvectionSchemeDoc), default='PLM')


      call set_tracer_advect_scheme(CS%default_advect_scheme, mesg)

      if(CS%default_advect_scheme == ADVECT_PPMH3) then
      call get_param(param_file, mdl, "USE_HUYNH_STENCIL_BUG", CS%useHuy&
     &nhStencilBug, desc="If true, use a stencil width of 2 in PPM:H3 tr&
     &acer advection. " // "This is incorrect and will produce regressio&
     &ns in certain " // "configurations, but may be required to reprodu&
     &ce results in " // "legacy simulations.", default=.false.)


      endif

!$omp   target enter data map(to: CS)

      id_clock_advect = cpu_clock_id('(Ocean advect tracer)', grain=CLOC&
     &K_MODULE)
#line 1528
      id_clock_pass = cpu_clock_id('(Ocean tracer halo updates)', grain=&
     &CLOCK_ROUTINE)
#line 1529
      id_clock_sync = cpu_clock_id('(Ocean tracer global synch)', grain=&
     &CLOCK_ROUTINE)
      end subroutine tracer_advect_init


      subroutine tracer_advect_end(CS)
      type(tracer_advect_CS), pointer :: CS

!$omp   target exit data map(delete: CS)
      if(associated(CS)) deallocate(CS)

      end subroutine tracer_advect_end
#line 1567
      end module MOM_tracer_advect
