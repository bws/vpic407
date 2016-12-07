!---------------------------------------------------------------------------------------
! parallel conversion
!---------------------------------------------------------------------------------------

module MPI
  include "mpif.h"                                                                                         
  integer myid,numprocs,ierr                                                                               
  integer master  

  ! MPI IO stuff
  integer nfiles, nbands
  integer sizes(3), subsizes(3), starts(3) , output_format, continuous, file_per_slice
  integer fileinfo, ierror, filetype, status(MPI_STATUS_SIZE)
  integer(kind=MPI_OFFSET_KIND) :: disp, offset
  integer fh

  integer append_to_files

  character (256), allocatable :: fnames(:)
  CHARACTER*(256) cfname

  parameter(continuous=1)
  parameter(file_per_slice=2)
  parameter(nfiles=82)
  parameter(nbands=5)
  parameter(master=0)
 
end module MPI

module topology
implicit none
  integer topology_x,topology_y,topology_z
  real(kind=8) tx,ty,tz
  integer, allocatable :: domain_size(:,:,:,:), idxstart(:,:), idxstop(:,:) 

  type :: ht_type
     
     integer(kind=4) :: tx,ty,tz         ! number of processes in x,y,z
     integer(kind=4) :: nx,ny,nz         ! number of cells in each direction that belong to this process
     integer(kind=4) :: start(3),stop(3) ! where to start/stop in x/y/z
     integer(kind=4) :: ix,iy,iz

  end type ht_type

  type(ht_type) :: ht


end module topology

program translate
  use topology
  use MPI
  implicit none
  integer(kind=4)it,itype,ndim,ndomains,decomp,n,nc(3),record_length,ix,iy,iz,yidx, ib, f, nfiles_total
  integer(kind=4) tslice_start,tslice_stop
  integer(kind=4)nx,ny,nz,nxstart,nxstop,output_record,tindex,tindex_start,tindex_stop,nout,i,j,error,nzstop,nzstart,k, tindex_new
  integer(kind=8) dom_x, dom_y, dom_z,write_individual_us
  real(kind=4)time,n_factor_top, n_factor_bottom
  integer(kind=4) httx,htty,httz
  real(kind=8) nx_d,ny_d,nz_d,mi_me,dt
  real(kind=8) diff,xmax,ymax,zmax
  real(kind=4), allocatable, dimension(:,:,:) :: ex,ey,ez,bx,by,bz,jx,jy,jz,rho,ne,ux,uy,uz,&
       pxx,pyy,pzz,pxy,pxz,pyz,mix1,mix2,ne_top,ne_bottom,ne_tmp2
  real(kind=4), allocatable, dimension(:,:,:) :: ex_ave,ey_ave,ez_ave,bx_ave,by_ave,bz_ave,&
       uex_ave,uey_ave,uez_ave,ne_ave,ni_ave,pe_xx_ave,pe_yy_ave,pe_zz_ave,pe_xy_ave,pe_xz_ave,&
       pe_yz_ave,pi_xx_ave,pi_yy_ave,pi_zz_ave,pi_xy_ave,pi_xz_ave,pi_yz_ave,uix_ave,uiy_ave,&
       uiz_ave,mix_e_ave,mix_i_ave
  real(kind=4), allocatable, dimension(:,:,:) :: buffer,absJ,absB,ux_top,uy_top,uz_top,ux_bot,&
       uy_bot,uz_bot,jx_ave,jy_ave,jz_ave
  real(kind=4), allocatable, dimension(:,:,:,:) :: eb
  character(256) fname,fname1
  logical dfile,check,write_average

! Define structure for V0 header

  type::v0header
     integer(kind=4) :: version, type, nt, nx, ny, nz
     real(kind=4) :: dt, dx, dy, dz
     real(kind=4) :: x0, y0, z0
     real(kind=4) :: cvac, eps0, damp
     integer(kind=4) :: rank, ndom, spid, spqm
  end type v0header

  type :: fieldstruct
     real(kind=4) :: ex, ey, ez, div_e_err         ! Electric field and div E error
     real(kind=4) :: cbx, cby, cbz, div_b_err      ! Magnetic field and div B error
     real(kind=4) :: tcax, tcay, tcaz, rhob        ! TCA fields and bound charge density
     real(kind=4) :: jfx, jfy, jfz, rhof           ! Free current and charge density
     integer(kind=2) :: ematx,ematy, ematz, nmat   ! Material at edge centers and nodes
     integer(kind=2) :: fmatx, fmaty, fmatz, cmat  ! Material at face and cell centers
  end type fieldstruct

  type :: hydrostruct
     real(kind=4) :: jx, jy, jz, rho  ! Current and charge density => <q v_i f>, <q f>
     real(kind=4) :: px, py, pz, ke   ! Momentum and K.E. density  => <p_i f>, <m c^2 (gamma-1) f>
     real(kind=4) :: txx, tyy, tzz    ! Stress diagonal            => <p_i v_j f>, i==j
     real(kind=4) :: tyz, tzx, txy    ! Stress off-diagonal        => <p_i v_j f>, i!=j
     real(kind=4) :: pad1,pad2        ! 16-byte align
  end type hydrostruct

  ! this describes the topology as viewed by the conversion programm

! Declare the structures

  type(v0header) :: v0
  type(fieldstruct), allocatable, dimension(:,:,:) :: field
  type(hydrostruct), allocatable, dimension(:,:,:) :: hydro

! data structure for the configuration file

  namelist /datum/ httx,htty,httz,tslice_start,tslice_stop,output_format,append_to_files 
  !namelist /datum/ httx,htty,httz,tslice_start,tslice_stop,n_factor_bottom,n_factor_top,output_format,append_to_files 


! init MPI 

  call MPI_INIT(ierr)                                                                                      
  call MPI_COMM_RANK(MPI_COMM_WORLD, myid, ierr)                                                           
  call MPI_COMM_SIZE(MPI_COMM_WORLD, numprocs, ierr)                            
                         
! read the configuration file

  if (myid==master) then
     open(unit=10,file='icon.txt',form='formatted',status='old')
     read(10,datum)
     close(10)
  endif

  call MPI_BCAST(httx,1,MPI_INTEGER,master,MPI_COMM_WORLD,ierr)
  call MPI_BCAST(htty,1,MPI_INTEGER,master,MPI_COMM_WORLD,ierr)
  call MPI_BCAST(httz,1,MPI_INTEGER,master,MPI_COMM_WORLD,ierr)

  call MPI_BCAST(tslice_start,1,MPI_INTEGER,master,MPI_COMM_WORLD,ierr)
  call MPI_BCAST(tslice_stop,1,MPI_INTEGER,master,MPI_COMM_WORLD,ierr)

  !call MPI_BCAST(n_factor_top,1,MPI_REAL4,master,MPI_COMM_WORLD,ierr)
  !call MPI_BCAST(n_factor_bottom,1,MPI_REAL4,master,MPI_COMM_WORLD,ierr)

  call MPI_BCAST(output_format,1,MPI_INTEGER,master,MPI_COMM_WORLD,ierr)
  call MPI_BCAST(append_to_files,1,MPI_INTEGER,master,MPI_COMM_WORLD,ierr)


! describe the topology of the conversion program

  ht%tx = httx
  ht%ty = htty
  ht%tz = httz

! do we want to save velocities of the individual species

  write_individual_us = 0

! read the info file

  open(unit=10,file='info.bin',status='old',form='unformatted',access='stream')
  read(10)tx
  read(10)ty
  read(10)tz
  
  read(10)xmax
  read(10)ymax
  read(10)zmax
  
  read(10)nx_d
  read(10)ny_d
  read(10)nz_d
  
  read(10)dt
  
  read(10)mi_me

  close(10)
   
  topology_x = floor(tx+0.5)
  topology_y = floor(ty+0.5)
  topology_z = floor(tz+0.5)

  nx = floor(nx_d + 0.5)
  ny = floor(ny_d + 0.5)
  nz = floor(nz_d + 0.5)

  ! check the topology for consistency

  if ( (ht%tx*ht%ty*ht%tz /= numprocs).or.(topology_x/ht%tx*ht%tx /= topology_x).or.&
       (topology_z/ht%tz*ht%tz /= topology_z).or.(topology_y/ht%ty*ht%ty /= topology_y) ) then

     if (myid == master) print *, "invalid converter topology"
     call MPI_FINALIZE(ierr)
     stop

  endif


  ! convert myid to homer indeces

  ht%ix  = myid
  ht%iy  = ht%ix/ht%tx
  ht%ix  = ht%ix - ht%iy*ht%tx
  ht%iz  = ht%iy/ht%ty 
  ht%iy  = ht%iy - ht%iz*ht%ty

  ! domain start/stop for this process

  ht%start(1)= topology_x/ht%tx*ht%ix  
  ht%stop(1) = topology_x/ht%tx*(ht%ix + 1) - 1 

  ht%start(2)= topology_y/ht%ty*ht%iy  
  ht%stop(2) = topology_y/ht%ty*(ht%iy + 1) - 1 

  ht%start(3)= topology_z/ht%tz*ht%iz 
  ht%stop(3) = topology_z/ht%tz*(ht%iz + 1) - 1 


  ! numner of cells for each process

  ht%nx = nx/ht%tx
  ht%ny = ny/ht%ty
  ht%nz = nz/ht%tz

  if (myid==master) then

     print *, "-----------------------------------------------"
     print *, " Topology: ", topology_x, topology_y, topology_z
     print *, " nx,nz,nz: ", nx,ny,nz
     print *, " ht: nx,ny: ", ht%nx,ht%ny,ht%nz
     print *, " mass ratio: ", mi_me
     print *, "-----------------------------------------------"
     
  endif

! total number of domains

  ndomains=topology_x*topology_y*topology_z

  allocate(domain_size(topology_x,topology_y,topology_z,3))
  allocate(idxstart(ndomains,3))
  allocate(idxstop(ndomains,3))

! determine total size of global problem

  do n = 1,ndomains
     
     call rank_to_index(n-1,ix,iy,iz)

     domain_size(ix+1,iy+1,iz+1,1) = (nx/topology_x)
     domain_size(ix+1,iy+1,iz+1,2) = (ny/topology_y)
     domain_size(ix+1,iy+1,iz+1,3) = (nz/topology_z)

     idxstart(n,1) = ( (nx/topology_x))*ix+1 - ht%nx*ht%ix
     idxstart(n,2) = ( (ny/topology_y))*iy+1 - ht%ny*ht%iy
     idxstart(n,3) = ( (nz/topology_z))*iz+1 - ht%nz*ht%iz

     idxstop(n,1)  = idxstart(n,1) +  (nx/topology_x) - 1
     idxstop(n,2)  = idxstart(n,2) +  (ny/topology_y) - 1 
     idxstop(n,3)  = idxstart(n,3) +  (nz/topology_z) - 1
     
  enddo

! Determine number of iterations between output files

if (myid == master) then

  dfile=.false.
  tindex= 0
  do while(.not.dfile)
     tindex=tindex+1
     write(fname,"(A9,I0,A,I0,A)")"fields/T.",tindex,"/fields.",tindex,".0"
     if (tindex .ne. 1) inquire(file=trim(fname),exist=dfile)
  enddo
  nout = tindex

! Total size of domain

  print *,"---------------------------------------------------"
  print *
  print *,"xmax=",xmax,"   ymax=",ymax,"   zmax=",zmax
  print *
  print *,"Iterations between output=",nout
  print *,"---------------------------------------------------"

endif

call MPI_BCAST(nout,1,MPI_INTEGER,master,MPI_COMM_WORLD,ierr)

tindex_start = tslice_start*nout
tindex_stop = tslice_stop*nout

! Need to determine the last record written,so we know which time slice to process next

if (append_to_files==1) then
   output_record = tslice_start + 1
else
   output_record = 1
endif
tindex = tindex_start


! Allocate storage space for fields and moments

  allocate(ex(ht%nx,ht%ny,ht%nz))
  allocate(ey(ht%nx,ht%ny,ht%nz))
  allocate(ez(ht%nx,ht%ny,ht%nz))
  allocate(bx(ht%nx,ht%ny,ht%nz))
  allocate(by(ht%nx,ht%ny,ht%nz))
  allocate(bz(ht%nx,ht%ny,ht%nz))

  allocate(ux(ht%nx,ht%ny,ht%nz))
  allocate(uy(ht%nx,ht%ny,ht%nz))
  allocate(uz(ht%nx,ht%ny,ht%nz))
  allocate(ne(ht%nx,ht%ny,ht%nz))
  allocate(pxx(ht%nx,ht%ny,ht%nz))
  allocate(pyy(ht%nx,ht%ny,ht%nz))
  allocate(pzz(ht%nx,ht%ny,ht%nz))
  allocate(pyz(ht%nx,ht%ny,ht%nz))
  allocate(pxz(ht%nx,ht%ny,ht%nz))
  allocate(pxy(ht%nx,ht%ny,ht%nz))

  allocate(mix1(ht%nx,ht%ny,ht%nz))
  !allocate(mix2(ht%nx,ht%ny,ht%nz))

  allocate(ne_tmp2(ht%nx,ht%ny,ht%nz))

  allocate(ne_top(ht%nx,ht%ny,ht%nz))
  allocate(ne_bottom(ht%nx,ht%ny,ht%nz))

  allocate(jx(ht%nx,ht%ny,ht%nz))
  allocate(jy(ht%nx,ht%ny,ht%nz))
  allocate(jz(ht%nx,ht%ny,ht%nz))

  allocate(absJ(ht%nx,ht%ny,ht%nz))
  allocate(absB(ht%nx,ht%ny,ht%nz))

  allocate(ux_top(ht%nx,ht%ny,ht%nz))
  allocate(uy_top(ht%nx,ht%ny,ht%nz))
  allocate(uz_top(ht%nx,ht%ny,ht%nz))

  allocate(ux_bot(ht%nx,ht%ny,ht%nz))
  allocate(uy_bot(ht%nx,ht%ny,ht%nz))
  allocate(uz_bot(ht%nx,ht%ny,ht%nz))

  allocate(ex_ave(ht%nx,ht%ny,ht%nz))
  allocate(ey_ave(ht%nx,ht%ny,ht%nz))
  allocate(ez_ave(ht%nx,ht%ny,ht%nz))
  allocate(bx_ave(ht%nx,ht%ny,ht%nz))
  allocate(by_ave(ht%nx,ht%ny,ht%nz))
  allocate(bz_ave(ht%nx,ht%ny,ht%nz))
  allocate(uex_ave(ht%nx,ht%ny,ht%nz))
  allocate(uey_ave(ht%nx,ht%ny,ht%nz))
  allocate(uez_ave(ht%nx,ht%ny,ht%nz))
  allocate(ne_ave(ht%nx,ht%ny,ht%nz))
  allocate(uix_ave(ht%nx,ht%ny,ht%nz))
  allocate(uiy_ave(ht%nx,ht%ny,ht%nz))
  allocate(uiz_ave(ht%nx,ht%ny,ht%nz))
  allocate(ni_ave(ht%nx,ht%ny,ht%nz))
  allocate(pe_xx_ave(ht%nx,ht%ny,ht%nz))
  allocate(pe_yy_ave(ht%nx,ht%ny,ht%nz))
  allocate(pe_zz_ave(ht%nx,ht%ny,ht%nz))
  allocate(pe_xy_ave(ht%nx,ht%ny,ht%nz))
  allocate(pe_xz_ave(ht%nx,ht%ny,ht%nz))
  allocate(pe_yz_ave(ht%nx,ht%ny,ht%nz))
  allocate(pi_xx_ave(ht%nx,ht%ny,ht%nz))
  allocate(pi_yy_ave(ht%nx,ht%ny,ht%nz))
  allocate(pi_zz_ave(ht%nx,ht%ny,ht%nz))
  allocate(pi_xy_ave(ht%nx,ht%ny,ht%nz))
  allocate(pi_xz_ave(ht%nx,ht%ny,ht%nz))
  allocate(pi_yz_ave(ht%nx,ht%ny,ht%nz))

  allocate(jx_ave(ht%nx,ht%ny,ht%nz))
  allocate(jy_ave(ht%nx,ht%ny,ht%nz))
  allocate(jz_ave(ht%nx,ht%ny,ht%nz))

  allocate(mix_i_ave(ht%nx,ht%ny,ht%nz))
  allocate(mix_e_ave(ht%nx,ht%ny,ht%nz))

  if (nbands > 0 ) allocate(eb(3*nbands,ht%nx,ht%ny,ht%nz))

  if (myid==master) then
          
     ! Write information file for IDL viewer

     open(unit=17,file='data/info',status='replace',form='unformatted')
     write(17)nx,ny,nz
     write(17)real(xmax,kind=4),real(ymax,kind=4),real(zmax,kind=4)
     close(17)
     
  endif  ! end of open files on master


! creat view, open MPI file, etc


  ! size of the global matrix

  sizes(1) = nx
  sizes(2) = ny
  sizes(3) = nz

  ! size of the chunck seen by each process

  subsizes(1) = ht%nx
  subsizes(2) = ht%ny
  subsizes(3) = ht%nz

  ! where each chunck starts

  starts(1) = ht%ix*ht%nx
  starts(2) = ht%iy*ht%ny
  starts(3) = ht%iz*ht%nz


  call MPI_TYPE_CREATE_SUBARRAY(3,sizes,subsizes,starts, MPI_ORDER_FORTRAN, MPI_REAL4, filetype, ierror)
  call MPI_TYPE_COMMIT(filetype, ierror)
  call MPI_INFO_CREATE(fileinfo,ierror)

  call MPI_INFO_SET(fileinfo,"romio_cb_write","enable",ierror)
  call MPI_INFO_SET(fileinfo,"romio_ds_write","disable",ierror)

  nfiles_total = nfiles+6*nbands
  allocate(fnames(nfiles_total))

  fnames(1) = 'ex'
  fnames(2) = 'ey'
  fnames(3) = 'ez'
  fnames(4) = 'bx'
  fnames(5) = 'by'
  fnames(6) = 'bz'

  fnames(7) = 'uix'
  fnames(8) = 'uiy'
  fnames(9) = 'uiz'
  fnames(10) = 'ni'
  fnames(11) = 'pi-xx'
  fnames(12) = 'pi-yy'
  fnames(13) = 'pi-zz'
  fnames(14) = 'pi-yz'
  fnames(15) = 'pi-xz'
  fnames(16) = 'pi-xy'

  fnames(17) = 'uex'
  fnames(18) = 'uey'
  fnames(19) = 'uez'
  fnames(20) = 'ne'
  fnames(21) = 'pe-xx'
  fnames(22) = 'pe-yy'
  fnames(23) = 'pe-zz'
  fnames(24) = 'pe-yz'
  fnames(25) = 'pe-xz'
  fnames(26) = 'pe-xy'

  fnames(27) = 'i-mix1'
  fnames(28) = 'e-mix1'

  fnames(29) = 'i-mix2'
  fnames(30) = 'e-mix2'

  fnames(31) = 'jx'
  fnames(32) = 'jy'
  fnames(33) = 'jz'

  fnames(34) = 'ni-bottom'
  fnames(35) = 'ni-top'

  fnames(36) = 'ne-bottom'
  fnames(37) = 'ne-top'

  fnames(38) = 'absB'
  fnames(39) = 'absJ'

  fnames(40) = 'uix-top'
  fnames(41) = 'uiy-top'
  fnames(42) = 'uiz-top'

  fnames(43) = 'uix-bot'
  fnames(44) = 'uiy-bot'
  fnames(45) = 'uiz-bot'

  fnames(46) = 'uex-top'
  fnames(47) = 'uey-top'
  fnames(48) = 'uez-top'

  fnames(49) = 'uex-bot'
  fnames(50) = 'uey-bot'
  fnames(51) = 'uez-bot'

! average

  fnames(52) = 'ex-ave'
  fnames(53) = 'ey-ave'
  fnames(54) = 'ez-ave'
  fnames(55) = 'bx-ave'
  fnames(56) = 'by-ave'
  fnames(57) = 'bz-ave'

  fnames(58) = 'uix-ave'
  fnames(59) = 'uiy-ave'
  fnames(60) = 'uiz-ave'
  fnames(61) = 'ni-ave'
  fnames(62) = 'pi-xx-ave'
  fnames(63) = 'pi-yy-ave'
  fnames(64) = 'pi-zz-ave'
  fnames(65) = 'pi-yz-ave'
  fnames(66) = 'pi-xz-ave'
  fnames(67) = 'pi-xy-ave'

  fnames(68) = 'uex-ave'
  fnames(69) = 'uey-ave'
  fnames(70) = 'uez-ave'
  fnames(71) = 'ne-ave'
  fnames(72) = 'pe-xx-ave'
  fnames(73) = 'pe-yy-ave'
  fnames(74) = 'pe-zz-ave'
  fnames(75) = 'pe-yz-ave'
  fnames(76) = 'pe-xz-ave'
  fnames(77) = 'pe-xy-ave'

  fnames(78) = 'jx-ave'
  fnames(79) = 'jy-ave'
  fnames(80) = 'jz-ave'

  fnames(81) = 'mix_e-ave'
  fnames(82) = 'mix_i-ave'


  do ib = 1,nbands
     write(fnames(nfiles+ib),"(A,I2.2)")"iEB-bot",ib
     write(fnames(nfiles+ib+nbands),"(A,I2.2)")"iEB-top",ib
     write(fnames(nfiles+ib+2*nbands),"(A,I2.2)")"iEB",ib

     write(fnames(nfiles+ib+3*nbands),"(A,I2.2)")"eEB-bot",ib
     write(fnames(nfiles+ib+4*nbands),"(A,I2.2)")"eEB-top",ib
     write(fnames(nfiles+ib+5*nbands),"(A,I2.2)")"eEB",ib
  enddo

! Loop over time slices

  dfile=.true.
  do while(dfile)

     if (myid==master) print *, " processing fields; time slice:",tindex

     do dom_x = ht%start(1),ht%stop(1)
        do dom_y = ht%start(2),ht%stop(2)
           do dom_z = ht%start(3), ht%stop(3)

              call index_to_rank(dom_x,dom_y,dom_z,n)

! Read in field data and load into global arrays

              write(fname,"(A9,I0,A8,I0,A1,I0)")"fields/T.",tindex,"/fields.",tindex,".",n-1        

              ! Index 0 does not have proper current, so use index 1 if it exists
              if (tindex == 0) then
                 write(fname1,"(A18,I0,A1,I0)")"fields/T.1/fields.",1,".",n-1        
                 inquire(file=trim(fname1),exist=check)
                 if (check) fname=fname1
              endif
              inquire(file=trim(fname),exist=check)
              

              
              if (check) then 
                 open(unit=10,file=trim(fname),status='unknown',form='unformatted',access='stream')
              else
                 print *,"Can't find file:",fname
                 print *
                 print *," ***  Terminating ***"
                 stop
              endif
              call read_boilerplate(10)
              read(10)v0
              read(10)itype
              read(10)ndim
              read(10)nc
              allocate(buffer(nc(1),nc(2),nc(3)))     
              
              call read_quantity(ex,n,nc,buffer,0)
              call read_quantity(ey,n,nc,buffer,0)
              call read_quantity(ez,n,nc,buffer,0)

!              read(10)buffer   ! skip div_e error

              call read_quantity(bx,n,nc,buffer,0)
              call read_quantity(by,n,nc,buffer,0)
              call read_quantity(bz,n,nc,buffer,0)
        
              close(10)

! ====================================
! BOTTOM ion hydro
! ====================================

              write(fname,"(A,I0,A,I0,A,I0)")"hydro/T.",tindex,"/HBothydro.",tindex,".",n-1        
              if (check) then 
                 open(unit=10,file=trim(fname),status='unknown',form='unformatted',access='stream')
              else
                 print *,"Can't find file:",fname
                 print *
                 print *," ***  Terminating ***"
                 stop
              endif
              call read_boilerplate(10)
              read(10)v0
              read(10)itype
              read(10)ndim
              read(10)nc


              call read_quantity(ux_bot,n,nc,buffer,0)
              call read_quantity(uy_bot,n,nc,buffer,0)
              call read_quantity(uz_bot,n,nc,buffer,0)

              ux(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   ux_bot(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              uy(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   uy_bot(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              uz(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   uz_bot(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 


              call read_quantity(ne_bottom,n,nc,buffer,0)

              ne_bottom(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   abs(ne_bottom(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)))
              
              ne(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   ne_bottom(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              !ne_tmp2( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) =  &
              !     ne_bottom( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )/n_factor_bottom
              
              mix1(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   ne_bottom(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3))

              !mix2(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
              !     ne_bottom(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3))/n_factor_bottom


 !             read(10)buffer ! skip KE energy
              
              call read_quantity(pxx,n,nc,buffer,0)
              call read_quantity(pyy,n,nc,buffer,0)
              call read_quantity(pzz,n,nc,buffer,0)
              call read_quantity(pyz,n,nc,buffer,0)
              call read_quantity(pxz,n,nc,buffer,0)
              call read_quantity(pxy,n,nc,buffer,0)


              do ib=1,nbands
                 read(10)buffer
                 eb( ib,idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
                      buffer(2:nc(1)-1,2:nc(2)-1,2:nc(3)-1)
                 
                 eb( ib+2*nbands,idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                      buffer(2:nc(1)-1,2:nc(2)-1,2:nc(3)-1)*&
                      ne_bottom( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 
              enddo

              close(10)

! ==============================================
! TOP ion hydro
! ==============================================

              write(fname,"(A,I0,A,I0,A,I0)")"hydro/T.",tindex,"/HTophydro.",tindex,".",n-1        
              if (check) then 
                 open(unit=10,file=trim(fname),status='unknown',form='unformatted',access='stream')
              else
                 print *,"Can't find file:",fname
                 print *
                 print *," ***  Terminating ***"
                 stop
              endif
              call read_boilerplate(10)
              read(10)v0
              read(10)itype
              read(10)ndim
              read(10)nc


              call read_quantity(ux_top,n,nc,buffer,0)
              call read_quantity(uy_top,n,nc,buffer,0)
              call read_quantity(uz_top,n,nc,buffer,0)

              ux(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   ux(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) + &
                   ux_top(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              uy(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   uy(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) + &
                   uy_top(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              uz(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   uz(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) + &
                   uz_top(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 


              call read_quantity(ne_top,n,nc,buffer,0)
              
              ne_top( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) =  &
                   abs(ne_top( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ))
                            
              ne( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
                   ne( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )  + &
                   ne_top( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) 

              !ne_tmp2( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
              !     ne_tmp2( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )  + &
              !     ne_top( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )/n_factor_top

              mix1( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) =  &
                   mix1(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) -  & 
                   ne_top(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3))
              
              !mix2( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) =  &
              !     mix2(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) -  & 
              !     ne_top(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3))/n_factor_top

 !             read(10)buffer ! skip KE energy
              
              call read_quantity(pxx,n,nc,buffer,1)
              call read_quantity(pyy,n,nc,buffer,1)
              call read_quantity(pzz,n,nc,buffer,1)
              call read_quantity(pyz,n,nc,buffer,1)
              call read_quantity(pxz,n,nc,buffer,1)
              call read_quantity(pxy,n,nc,buffer,1)


              do ib=1,nbands
                 read(10)buffer
                 eb( ib+2*nbands,idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
                      eb( ib+2*nbands,idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )  &
                      + buffer(2:nc(1)-1,2:nc(2)-1,2:nc(3)-1)*&
                      ne_top( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )
                 
                 eb( ib+nbands,idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
                      + buffer(2:nc(1)-1,2:nc(2)-1,2:nc(3)-1)

              enddo

              close(10)

!  end read
              deallocate(buffer)
              

           enddo ! domain_z loop
        enddo ! domain_y loop
     enddo !domain x

     jx = ux
     jy = uy
     jz = uz

     where (ne_top > 0.0) 
        ux_top = (ux_top/ne_top)
        uy_top = (uy_top/ne_top)
        uz_top = (uz_top/ne_top)
     endwhere

     where (ne_bottom > 0.0) 
        ux_bot = (ux_bot/ne_bottom)
        uy_bot = (uy_bot/ne_bottom)
        uz_bot = (uz_bot/ne_bottom)
     endwhere
     
     where (ne > 0.0) 
        pxx = (pxx - mi_me*ux*ux/ne)
        pyy = (pyy - mi_me*uy*uy/ne)
        pzz = (pzz - mi_me*uz*uz/ne)
        pxy = (pxy - mi_me*ux*uy/ne)
        pxz = (pxz - mi_me*ux*uz/ne)
        pyz = (pyz - mi_me*uy*uz/ne)
        ux = (ux/ne)
        uy = (uy/ne)
        uz = (uz/ne)

        mix1 = mix1/ne
        !mix2 = mix2/ne_tmp2
                
     elsewhere
        pxx = 0.0
        pyy = 0.0
        pzz = 0.0
        pxy = 0.0
        pxz = 0.0
        pyz = 0.0
        ux = 0.0
        uy = 0.0
        uz = 0.0
        mix1 = 0.0
        !mix2 = 0.0
     endwhere
   
     do ib=1,nbands
        where (ne > 0)
           eb( ib+2*nbands,:,:,:) = eb( ib+2*nbands,:,:,:)/ne
        endwhere
     enddo

     
     ! mkdir

     !if (myid==master) then
     !   write(cfname,"(A,I0)")'data/T.',tindex
     !   call makedir(trim(cfname))
     !   call system("mkdir " // trim(cfname))
     !endif

     call MPI_BARRIER(MPI_COMM_WORLD, ierror)

     ! WRITE FILE
     
     call write_data(fnames(1),ex,tindex,output_record)
     call write_data(fnames(2),ey,tindex,output_record)
     call write_data(fnames(3),ez,tindex,output_record)

     call write_data(fnames(4),bx,tindex,output_record)
     call write_data(fnames(5),by,tindex,output_record)
     call write_data(fnames(6),bz,tindex,output_record)

     call write_data(fnames(7),ux,tindex,output_record)
     call write_data(fnames(8),uy,tindex,output_record)
     call write_data(fnames(9),uz,tindex,output_record)

     call write_data(fnames(10),ne,tindex,output_record)

     call write_data(fnames(11),pxx,tindex,output_record)
     call write_data(fnames(12),pyy,tindex,output_record)
     call write_data(fnames(13),pzz,tindex,output_record)

     call write_data(fnames(14),pyz,tindex,output_record)
     call write_data(fnames(15),pxz,tindex,output_record)
     call write_data(fnames(16),pxy,tindex,output_record)


     call write_data(fnames(27),mix1,tindex,output_record)
!     call write_data(fnames(29),mix2,tindex,output_record)
!     call write_data(fnames(34),ne_bottom,tindex,output_record)
!     call write_data(fnames(35),ne_top,tindex,output_record)

     if (write_individual_us == 1) then

        call write_data(fnames(40),ux_top,tindex,output_record)
        call write_data(fnames(41),uy_top,tindex,output_record)
        call write_data(fnames(42),uz_top,tindex,output_record)
        
        call write_data(fnames(43),ux_bot,tindex,output_record)
        call write_data(fnames(44),uy_bot,tindex,output_record)
        call write_data(fnames(45),uz_bot,tindex,output_record)

     endif

     absB = sqrt(bx**2 + by**2 + bz**2)
     call write_data(fnames(38),absB,tindex,output_record)

          
     do ib=1,nbands
        ! use ne_top as I/O buffer        
 !       ne_top = eb(ib,:,:,:)        
 !       call write_data(fnames(nfiles+ib),ne_top,tindex,output_record)

 !       ne_top = eb(ib+nbands,:,:,:)        
 !       call write_data(fnames(nfiles+ib+nbands),ne_top,tindex,output_record)
        
        ne_top = eb(ib+2*nbands,:,:,:)        
        call write_data(fnames(nfiles+ib+2*nbands),ne_top,tindex,output_record)
     enddo
     
     
! ===============================================================
!  BOTTOM electron hydro
! ===============================================================
     
     do dom_x = ht%start(1),ht%stop(1)
        do dom_y = ht%start(2),ht%stop(2)
           do dom_z = ht%start(3), ht%stop(3)
              
              call index_to_rank(dom_x,dom_y,dom_z,n)
              
              
              !   now read the bottom hydro
              
              write(fname,"(A,I0,A,I0,A,I0)")"hydro/T.",tindex,"/eBothydro.",tindex,".",n-1        
              if (check) then 
                 open(unit=10,file=trim(fname),status='unknown',form='unformatted',access='stream')
              else
                 print *,"Can't find file:",fname
                 print *
                 print *," ***  Terminating ***"
                 stop
              endif
              call read_boilerplate(10)
              read(10)v0
              read(10)itype
              read(10)ndim
              read(10)nc
              
              allocate(buffer(nc(1),nc(2),nc(3)))     

              call read_quantity(ux_bot,n,nc,buffer,0)
              call read_quantity(uy_bot,n,nc,buffer,0)
              call read_quantity(uz_bot,n,nc,buffer,0)

              ux(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   ux_bot(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              uy(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   uy_bot(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              uz(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   uz_bot(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              call read_quantity(ne_bottom,n,nc,buffer,0)

              ne_bottom(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   abs(ne_bottom(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)))
              
              ne(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   ne_bottom(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              !ne_tmp2( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) =  &
              !     ne_bottom( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )/n_factor_bottom
              
              mix1(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   ne_bottom(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3))

              !mix2(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
              !     ne_bottom(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3))/n_factor_bottom


 !             read(10)buffer ! skip KE energy
              
              call read_quantity(pxx,n,nc,buffer,0)
              call read_quantity(pyy,n,nc,buffer,0)
              call read_quantity(pzz,n,nc,buffer,0)
              call read_quantity(pyz,n,nc,buffer,0)
              call read_quantity(pxz,n,nc,buffer,0)
              call read_quantity(pxy,n,nc,buffer,0)


              do ib=1,nbands
                 read(10)buffer
                 eb( ib,idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
                      buffer(2:nc(1)-1,2:nc(2)-1,2:nc(3)-1)
                 
                 eb( ib+2*nbands,idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
                      buffer(2:nc(1)-1,2:nc(2)-1,2:nc(3)-1)*&
                      ne_bottom( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 
              enddo
              
              close(10)

! ==============================================
! TOP electron hydro
! ==============================================

              write(fname,"(A,I0,A,I0,A,I0)")"hydro/T.",tindex,"/eTophydro.",tindex,".",n-1        
              if (check) then 
                 open(unit=10,file=trim(fname),status='unknown',form='unformatted',access='stream')
              else
                 print *,"Can't find file:",fname
                 print *
                 print *," ***  Terminating ***"
                 stop
              endif
              call read_boilerplate(10)
              read(10)v0
              read(10)itype
              read(10)ndim
              read(10)nc
              

              call read_quantity(ux_top,n,nc,buffer,0)
              call read_quantity(uy_top,n,nc,buffer,0)
              call read_quantity(uz_top,n,nc,buffer,0)

              ux(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   ux(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) + &
                   ux_top(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              uy(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   uy(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) + &
                   uy_top(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              uz(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) = &
                   uz(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) + &
                   uz_top(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) 

              call read_quantity(ne_top,n,nc,buffer,0)
              
              ne_top( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) =  &
                   abs(ne_top( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ))
                            
              ne( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
                   ne( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )  + &
                   ne_top( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) 

              !ne_tmp2( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
              !     ne_tmp2( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )  + &
              !     ne_top( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )/n_factor_top

              mix1( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) =  &
                   mix1(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) -  & 
                   ne_top(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3))
              
              !mix2( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) =  &
              !     mix2(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3)) -  & 
              !     ne_top(idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3))/n_factor_top

 !             read(10)buffer ! skip KE energy
              
              call read_quantity(pxx,n,nc,buffer,1)
              call read_quantity(pyy,n,nc,buffer,1)
              call read_quantity(pzz,n,nc,buffer,1)
              call read_quantity(pyz,n,nc,buffer,1)
              call read_quantity(pxz,n,nc,buffer,1)
              call read_quantity(pxy,n,nc,buffer,1)


              do ib=1,nbands
                 read(10)buffer
                 eb( ib+2*nbands,idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
                      eb( ib+2*nbands,idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )  &
                      + buffer(2:nc(1)-1,2:nc(2)-1,2:nc(3)-1)*&
                      ne_top( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) )
                 
                 eb( ib+nbands,idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
                      + buffer(2:nc(1)-1,2:nc(2)-1,2:nc(3)-1)

              enddo
              
              close(10)
              deallocate(buffer)

! ============== 
! TIME-AVERAGE
! ==============

!              write(fname,"(A,I0,A,I0,A,I0)")"hydro-ave/T.",tindex,"/data-ave.",tindex,".",n-1        
!              inquire(file=trim(fname),exist=write_average)
!              if (write_average) then 
!                 open(unit=10,file=trim(fname),status='unknown',form='unformatted',access='stream')
!              else
!                 if (myid==master) print *,"No time-average data for slice: ",tindex
!              endif
              
!              if (write_average) then

!                 allocate(buffer(nc(1)-2,nc(2)-2,nc(3)-2))                   
                 
!                 read(10)buffer
!                 bx_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
!                 read(10)buffer
!                 by_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
!                 read(10)buffer
!                 bz_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 ex_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
!                 read(10)buffer
!                 ey_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
!                 read(10)buffer
!                 ez_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 uex_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
!                 read(10)buffer
!                 uey_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
!                 read(10)buffer
!                 uez_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 uix_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
!                 read(10)buffer
!                 uiy_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
!                 read(10)buffer
!                 uiz_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pe_xx_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pe_yy_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pe_zz_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pe_xy_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pe_xz_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pe_yz_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pi_xx_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pi_yy_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pi_zz_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pi_xy_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pi_xz_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 pi_yz_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 ne_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 read(10)buffer
!                 ni_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)


!                 read(10)buffer
!                 mix_e_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)

!                 read(10)buffer
!                 mix_i_ave( idxstart(n,1):idxstop(n,1),idxstart(n,2):idxstop(n,2),idxstart(n,3):idxstop(n,3) ) = &
!                      + buffer(:,:,:)
                 
!                 close(10)
!                 deallocate(buffer)

 !             endif
              
              
           enddo ! domain_z loop
        enddo ! domain y
     enddo ! domain_x loop

     jx = jx + ux
     jy = jy + uy
     jz = jz + uz
     
     where (ne_top > 0.0) 
        ux_top = -(ux_top/ne_top)
        uy_top = -(uy_top/ne_top)
        uz_top = -(uz_top/ne_top)
     endwhere

     where (ne_bottom > 0.0) 
        ux_bot = -(ux_bot/ne_bottom)
        uy_bot = -(uy_bot/ne_bottom)
        uz_bot = -(uz_bot/ne_bottom)
     endwhere

     
     where (ne > 0.0) 
        pxx = (pxx - ux*ux/ne)
        pyy = (pyy - uy*uy/ne)
        pzz = (pzz - uz*uz/ne)
        pxy = (pxy - ux*uy/ne)
        pxz = (pxz - ux*uz/ne)
        pyz = (pyz - uy*uz/ne)
        ux = -(ux/ne)
        uy = -(uy/ne)
        uz = -(uz/ne)

        mix1 = mix1/ne
        !mix2 = mix2/ne_tmp2
     elsewhere
        pxx = 0.0
        pyy = 0.0
        pzz = 0.0
        pxy = 0.0
        pxz = 0.0
        pyz = 0.0
        ux = 0.0
        uy = 0.0
        uz = 0.0

        mix1 = 0.0
        !mix2 = 0.0

     endwhere
         

!     if (write_average) then

        ! time-averaged data
        
!        jx_ave = uex_ave + uix_ave
!        jy_ave = uey_ave + uiy_ave
!        jz_ave = uez_ave + uiz_ave
        
!        where (ne_ave > 0.0) 
           
!           pe_xx_ave = (pe_xx_ave - uex_ave*uex_ave/ne_ave)
!           pe_yy_ave = (pe_yy_ave - uey_ave*uey_ave/ne_ave)
!           pe_zz_ave = (pe_zz_ave - uez_ave*uez_ave/ne_ave)
!           pe_xy_ave = (pe_xy_ave - uex_ave*uey_ave/ne_ave)
!           pe_xz_ave = (pe_xz_ave - uex_ave*uez_ave/ne_ave)
!           pe_yz_ave = (pe_yz_ave - uey_ave*uez_ave/ne_ave)
           
!           uex_ave = -(uex_ave/ne_ave)
!           uey_ave = -(uey_ave/ne_ave)
!           uez_ave = -(uez_ave/ne_ave)
           
!        endwhere
        
!        where (ni_ave > 0.0) 
!           pi_xx_ave = (pi_xx_ave - mi_me*uix_ave*uix_ave/ni_ave)
!           pi_yy_ave = (pi_yy_ave - mi_me*uiy_ave*uiy_ave/ni_ave)
!           pi_zz_ave = (pi_zz_ave - mi_me*uiz_ave*uiz_ave/ni_ave)
!           pi_xy_ave = (pi_xy_ave - mi_me*uix_ave*uiy_ave/ni_ave)
!           pi_xz_ave = (pi_xz_ave - mi_me*uix_ave*uiz_ave/ni_ave)
!           pi_yz_ave = (pi_yz_ave - mi_me*uiy_ave*uiz_ave/ni_ave)
           
!           uix_ave = (uix_ave/ni_ave)
!           uiy_ave = (uiy_ave/ni_ave)
!           uiz_ave = (uiz_ave/ni_ave)
!        endwhere
        
        
        ! end time-aeraged
        
!     endif

     do ib=1,nbands
        where (ne > 0)
           eb( ib+2*nbands,:,:,:) = eb( ib+2*nbands,:,:,:)/ne
        endwhere
     enddo


     call write_data(fnames(17),ux,tindex,output_record)
     call write_data(fnames(18),uy,tindex,output_record)
     call write_data(fnames(19),uz,tindex,output_record)

     call write_data(fnames(20),ne,tindex,output_record)

     call write_data(fnames(21),pxx,tindex,output_record)
     call write_data(fnames(22),pyy,tindex,output_record)
     call write_data(fnames(23),pzz,tindex,output_record)

     call write_data(fnames(24),pyz,tindex,output_record)
     call write_data(fnames(25),pxz,tindex,output_record)
     call write_data(fnames(26),pxy,tindex,output_record)

     call write_data(fnames(31),jx,tindex,output_record)
     call write_data(fnames(32),jy,tindex,output_record)
     call write_data(fnames(33),jz,tindex,output_record)


     call write_data(fnames(28),mix1,tindex,output_record)
!     call write_data(fnames(30),mix2,tindex,output_record)

!     call write_data(fnames(36),ne_bottom,tindex,output_record)
!     call write_data(fnames(37),ne_top,tindex,output_record)

     if (write_individual_us == 1) then

        call write_data(fnames(46),ux_top,tindex,output_record)
        call write_data(fnames(47),uy_top,tindex,output_record)
        call write_data(fnames(48),uz_top,tindex,output_record)
        
        call write_data(fnames(49),ux_bot,tindex,output_record)
        call write_data(fnames(50),uy_bot,tindex,output_record)
        call write_data(fnames(51),uz_bot,tindex,output_record)

     endif


     absJ = sqrt(jx**2 + jy**2 + jz**2)
     call write_data(fnames(39),absJ,tindex,output_record)
          
     do ib=1,nbands
        ! use ne_top as I/O buffer        
!        ne_top = eb(ib,:,:,:)        
!        call write_data(fnames(nfiles+ib+3*nbands),ne_top,tindex,output_record)

!        ne_top = eb(ib+nbands,:,:,:)        
!        call write_data(fnames(nfiles+ib+4*nbands),ne_top,tindex,output_record)
        
        ne_top = eb(ib+2*nbands,:,:,:)        
        call write_data(fnames(nfiles+ib+5*nbands),ne_top,tindex,output_record)
     enddo

     ! write time-averaged data
     
!     if (write_average) then
!        call write_data(fnames(52),ex_ave,tindex,output_record)
!        call write_data(fnames(53),ey_ave,tindex,output_record)
!        call write_data(fnames(54),ez_ave,tindex,output_record)

!        call write_data(fnames(55),bx_ave,tindex,output_record)
!        call write_data(fnames(56),by_ave,tindex,output_record)
!        call write_data(fnames(57),bz_ave,tindex,output_record)

!        call write_data(fnames(58),uix_ave,tindex,output_record)
!        call write_data(fnames(59),uiy_ave,tindex,output_record)
!        call write_data(fnames(60),uiz_ave,tindex,output_record)
!        call write_data(fnames(61),ni_ave,tindex,output_record)

!        call write_data(fnames(62),pi_xx_ave,tindex,output_record)
!        call write_data(fnames(63),pi_yy_ave,tindex,output_record)
!        call write_data(fnames(64),pi_zz_ave,tindex,output_record)
!        call write_data(fnames(65),pi_yz_ave,tindex,output_record)
!        call write_data(fnames(66),pi_xz_ave,tindex,output_record)
!        call write_data(fnames(67),pi_xy_ave,tindex,output_record)

!        call write_data(fnames(68),uex_ave,tindex,output_record)
!        call write_data(fnames(69),uey_ave,tindex,output_record)
!        call write_data(fnames(70),uez_ave,tindex,output_record)
!        call write_data(fnames(71),ne_ave,tindex,output_record)

!        call write_data(fnames(72),pe_xx_ave,tindex,output_record)
!        call write_data(fnames(73),pe_yy_ave,tindex,output_record)
!        call write_data(fnames(74),pe_zz_ave,tindex,output_record)
!        call write_data(fnames(75),pe_yz_ave,tindex,output_record)
!        call write_data(fnames(76),pe_xz_ave,tindex,output_record)
!        call write_data(fnames(77),pe_xy_ave,tindex,output_record)

!        call write_data(fnames(78),jx_ave,tindex,output_record)
!        call write_data(fnames(79),jy_ave,tindex,output_record)
!        call write_data(fnames(80),jz_ave,tindex,output_record)

!        call write_data(fnames(81),mix_e_ave,tindex,output_record)
!        call write_data(fnames(82),mix_i_ave,tindex,output_record)



!     endif

     ! Check if there is another time slice to read
     
     
     if (myid==master) then
        dfile = .false.
        tindex_new=tindex
        do while ((.not.dfile).and.(tindex_new < tindex+nout).and.(tindex_new <=tindex_stop))        
           tindex_new=tindex_new+1
           if (tindex_new .GT. 1) then
              write(fname,"(A9,I0,A,I0,A)")"fields/T.",tindex_new,"/fields.",tindex_new,".0"
              inquire(file=trim(fname),exist=dfile)
           endif
        enddo

     endif

     call MPI_BCAST(tindex_new,1,MPI_INTEGER,master,MPI_COMM_WORLD,ierr)
     call MPI_BCAST(dfile,1,MPI_LOGICAL,master,MPI_COMM_WORLD,ierr)

     tindex=tindex_new     
     if (dfile) output_record=output_record+1
     
  enddo ! time loop
  

  call MPI_BARRIER(MPI_COMM_WORLD, ierror)
  call MPI_FINALIZE(ierr)
  
end program translate

subroutine read_boilerplate(nfile)
  implicit none
  integer(kind=1)sizearr(5)
  integer(kind=2)cafevar 
  integer(kind=4)deadbeefvar
  real(kind=4)realone
  real(kind=8)doubleone
  integer nfile
  read(10)sizearr
  read(10)cafevar
  read(10)deadbeefvar
  read(10)realone
  read(10)doubleone
!  print *, sizearr,cafevar, deadbeefvar, realone, doubleone
  return
end subroutine read_boilerplate

!

subroutine rank_to_index(rank,ix,iy,iz) 
use topology
implicit none
integer iix, iiy, iiz, rank,ix,iy,iz

iix  = rank
iiy  = iix/topology_x
iix  = iix - iiy*topology_x
iiz  = iiy/topology_y 
iiy  = iiy - iiz*topology_y

ix = iix
iy = iiy
iz = iiz

end subroutine rank_to_index


subroutine index_to_rank(ix,iy,iz,rank)
use topology
implicit none
integer(kind=8) ix,iy,iz,iix,iiy,iiz
integer rank

iix = mod(ix,topology_x)
iiy = mod(iy,topology_y)
iiz = mod(iz,topology_z)

!  Compute the rank
rank = iix + topology_x*( iiy + topology_y*iiz ) + 1 

end subroutine index_to_rank

subroutine read_quantity(data,n,nc,buffer,sum)
use topology
implicit none
integer sum,n,nc(3)
real(kind=4) data(ht%nx,ht%ny,ht%nz), buffer(nc(1),nc(2),nc(3))

read(10)buffer
if (sum == 0) then
   data( idxstart(n,1):idxstop(n,1), idxstart(n,2):idxstop(n,2), idxstart(n,3):idxstop(n,3) ) = &
        buffer(2:nc(1)-1,2:nc(2)-2,2:nc(3)-1)
elseif (sum == 1) then
   data( idxstart(n,1):idxstop(n,1), idxstart(n,2):idxstop(n,2), idxstart(n,3):idxstop(n,3) ) = &
        data( idxstart(n,1):idxstop(n,1), idxstart(n,2):idxstop(n,2), idxstart(n,3):idxstop(n,3) ) &
        + buffer(2:nc(1)-1,2:nc(2)-2,2:nc(3)-1)
endif
   
end subroutine read_quantity


subroutine write_data(fname,data,tindex,output_record)
use topology
use mpi
implicit none
integer tindex,output_record
character *(*) fname
real(kind=4) data(ht%nx,ht%ny,ht%nz)
real(kind=8) mp_elapsed


mp_elapsed = MPI_WTIME()

if (output_format == 1) then
   
   offset = (output_record - 1)*ht%nx*ht%ny*ht%nz
   cfname = "data/" // trim(fname) // '.gda'
   call MPI_FILE_OPEN(MPI_COMM_WORLD, trim(cfname), MPI_MODE_RDWR+MPI_MODE_CREATE, fileinfo, fh, ierror)
   call MPI_FILE_SET_VIEW(fh,disp, MPI_REAL4, filetype, 'native', MPI_INFO_NULL, ierror)

else
   
   offset = 0
   write(cfname,"(A,A,A,I0,A)") "data/",trim(fname),'_',tindex,'.gda'
   !write(cfname,"(A,I0,A,A,A,I0,A)") "data/T.",tindex,"/",trim(fname),'_',tindex,'.gda'
   call MPI_FILE_OPEN(MPI_COMM_WORLD, trim(cfname), MPI_MODE_RDWR+MPI_MODE_CREATE, fileinfo, fh, ierror)
   call MPI_FILE_SET_VIEW(fh,disp, MPI_REAL4, filetype, 'native', MPI_INFO_NULL, ierror)
   
endif

if (ierror /= 0) then

   if (myid==master) print *, "cannnot open file ",trim(cfname)
   stop;

endif


if (myid==master) print *, "writing data to file ",trim(cfname)

call MPI_FILE_WRITE_AT_ALL(fh, offset, data, ht%nx*ht%ny*ht%nz, MPI_REAL4, status, ierror)


call MPI_FILE_CLOSE(fh,ierror)

mp_elapsed = MPI_WTIME() - mp_elapsed

if (myid==master) write(*,'(A, F5.1)') " => time(s):",mp_elapsed

end subroutine write_data
