#const day=1.


% Regardless of the model, if fix or not_sched values are passed, those of the previous solution must be kept fixed.
:- sat_pkt(Pat, Pkt_ID), not_schedulable(Pat, (Pkt_ID, Occ), day).  % Not necessary because the master does not assign it already
:- sat_pkt(Pat, Pkt_ID), not_schedulable(Pat, (Pkt_ID, Occ)).

:- not sat_pkt(Pat, Pkt_ID), fix_schedule(Pat, (Pkt_ID, Occ), day),
    necessity_tot_satisfied_fix(Pat, (Pkt_ID, Occ)).



%DEF
%%% -- CONTAINS SERVICE: useful predicate to lighten notation, determines whether a packet (instance) contains a certain service
contains_service(Pat, (Prot, Iter, Pkt), Srv) :- packet_type(Pat, Prot, Iter, Pkt, Type), service_in_packet(Type, Srv).

    %%% -- SERVICE is the basic element to be assigned to a time slot
service(Pat, Srv) :- schedule(Pat, (Pkt_ID, _), day), contains_service(Pat, Pkt_ID, Srv).


%GENERATE
    %%% -- With more than one units of the same kind the SP must decide to which the service has to be assigned
    %       The assigned CUop must be of the same type and unique.                                              %cut away unuseful grounding
0{provides(Res, CUop, Pat, Srv) : capacity(day, Res, CUop, _, _), service(Srv, Res, _, _)}1 :- service(Pat, Srv), not provides(Pat, Srv, Pat, Srv).
 
    %%% -- for each couple of services, 1 can precede 2, or not if they are parallel
{precedes(Pat1, Srv1, Pat2, Srv2)} :- service(Pat1, Srv1), provides(_, _, Pat1, Srv1), service(Pat2, Srv2), provides(_, _, Pat2, Srv2).
 
    %%% -- Assigning a time with dl: Start1 + Dur1 <= Start2 if 1 precedes 2
&diff { (Pat1,Srv1) - (Pat2,Srv2) } <= -Dur1 :- precedes(Pat1,Srv1,Pat2,Srv2), service(Srv1, _, Dur1, _).

%CONSTRAINTS
    %%% -- different services of the same patient cannot be deployed at the same time, 
    %      one precedes the other
:- not precedes(Pat, Srv1, Pat, Srv2), 
   not precedes(Pat, Srv2, Pat, Srv1), Srv1!=Srv2, 
   service(Pat, Srv1),
   service(Pat, Srv2), 
   provides(Res1, CUop1, Pat, Srv1), 
   provides(Res2, CUop2, Pat, Srv2), 
   Pat!=Res1, 
   Srv1!=CUop1, 
   Pat!=Res2, 
   Srv2!=CUop2.  %devo escludere il caso che si tratti di Pat=Unit e Srv=Operatore, ovvero la chiusura iniziale, il blocco fake

    %%% -- The same Unit operator (machine) is in use for only one 
    %      service of a patient, not for + services or pats 
    %      at the same time    
    %%% case of >1 Unit operators
:- not precedes(Pat1, Srv1, Pat2, Srv2), 
   not precedes(Pat2, Srv2, Pat1, Srv1), 
   service(Srv1, CU, _, _), 
   service(Srv2, CU, _, _),
   provides(CU, CUop, Pat1, Srv1), 
   provides(CU, CUop, Pat2, Srv2), 
   Pat1!=Pat2, 
   service(Pat1, Srv1), 
   service(Pat2, Srv2).

:- not precedes(Pat1, Srv1, Pat2, Srv2), 
   not precedes(Pat2, Srv2, Pat1, Srv1), 
   service(Srv1, CU, _, _), 
   service(Srv2, CU, _, _), 
   provides(CU, CUop, Pat1, Srv1), 
   provides(CU, CUop, Pat2, Srv2), 
   Srv1!=Srv2, 
   service(Pat1, Srv1), 
   service(Pat2, Srv2).

%CAPACITY CONSTRAINTS with time dl
    %%% -- Start >= OpenT
&diff { 0-(Pat,Srv) } <= - OpenT :- capacity(day, Res, CUop, OpenT, Q),
                                   provides(Res, CUop, Pat, Srv). 
    %%% -- Start + Dur =  End <= ClosT  = OpenT+Availability
&diff { (Pat,Srv)-0 } <= -Dur+OpenT+Q :- capacity(day, Res, CUop, OpenT, Q),
                                   provides(Res, CUop, Pat, Srv), service(Srv, Res, Dur, _). 


%DEFINE
    %%% -- a packet is satisfied if every contained service is provided
    sat_pkt(Pat, Pkt_ID)   :- provides(_, _, Pat, Srv) : contains_service(Pat, Pkt_ID, Srv); schedule(Pat, (Pkt_ID, _), day).
    unsat_pkt(Pat, Pkt_ID) :- schedule(Pat, (Pkt_ID, _), day), not sat_pkt(Pat, Pkt_ID).


%CONSTRAINT
    %%% -- Forbid the presence of a provided service that is not part of any satisfied packet (All the provided must be useful to satisfy at least one packet)
:- provides(_, _, Pat, Srv), not provides(Pat, Srv, Pat, Srv), #count{sat_pkt(PatX, Pkt_ID) : contains_service(PatX, Pkt_ID, Srv), PatX=Pat}=0.



#show service/2.
#show precedes/4.
#show provides/4.

#show sat_pkt/2.
#show unsat_pkt/2.
