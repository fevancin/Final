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

%%%%%% -- Shifted start of a care unit: create a fake service that precedes all the others assigned to that care unit
service(CU, CUop) :- capacity(day, CU, CUop, Start, _), Start>0.                           %Create
service(CUop, CU, Dur, 0)    :- service(CU, CUop), capacity(day, CU, CUop, Dur, _).         %Assign a Duration = Start
provides(CU, CUop, CU, CUop) :- service(CU, CUop), capacity(day, CU, CUop, _, _).           %Force the assignment of the that CUop 
start_time(CU, CUop, 0)      :- service(CU, CUop), capacity(day, CU, CUop, _, _).

time(0..Tmax) :- Tmax=#max{T : T=S+D, capacity(day,_,_,S,D)}.

%GENERATE
    %%% -- With more than one units of the same kind the SP must decide to which the service has to be assigned
    %       The assigned CUop must be of the same type and unique.                                              %cut away unuseful grounding
0{provides(CU, CUop, Pat, Srv) : capacity(day, CU, CUop, _, _), service(Srv, CU, _, _)}1 :- service(Pat, Srv), not provides(Pat, Srv, Pat, Srv).

1{start_time(Pat, Srv, Start) : time(Start)}1 :- service(Pat, Srv), provides(_, _, Pat, Srv).

%DEF
    %%% -- Precedes: A service precedes the other if the end of the former is not after the start of the latter
precedes(P1, S1, P2, S2) :- start_time(P1, S1, Start1), start_time(P2, S2, Start2), 
                            service(S1, _, D1, _), not care_unit(P1), not capacity(_,P1,S1,_,_), %if NOT fake block for delay
                            Start1 + D1 <= Start2.

precedes(CU, CUop, P, S) :- start_time(CU, CUop, Start1), start_time(P, S, Start2), 
                            service(CUop, CU, D1, _),  %if fake block for delay
                            Start1 + D1 <= Start2.

%Constraints
    %%% -- different services of the same patient cannot be deployed at the same time, 
    %      one precedes the other
:- not precedes(Pat, Srv1, Pat, Srv2), 
   not precedes(Pat, Srv2, Pat, Srv1), Srv1!=Srv2, 
   provides(_, _, Pat, Srv1), 
   provides(_, _, Pat, Srv2), 
   not care_unit(Pat), 
   not capacity(_,Pat,Srv1,_,_), 
   not capacity(_,Pat,Srv2,_,_).
    %NOT for fake block! e.g. red,1 e red,2 do not precede each other

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

    %%% -- Irreflexivity
:- precedes(Pat1, Srv1, Pat1, Srv1).

    %%% -- Antisimmetry
:- precedes(Pat1, Srv1, Pat1, Srv2), 
   precedes(Pat2, Srv2, Pat1, Srv1).

    %%% -- Transitivity
:- precedes(Pat1, Srv1, Pat2, Srv2), 
   precedes(Pat2, Srv2, Pat3, Srv3), 
   not precedes(Pat1, Srv1, Pat3, Srv3).

    %%% -- CAPACITY CONSTRAINT: (Strengthened) --> The sum of the durations of services that precede a service S 
%                                                over a chain, plus the duration of S, cannot exceed capacity
%					                             allocated for that care unit U associated to S
:- service(P,S), 
   service(S,CU,D,_), 
   provides(CU,CUop,P,S), 
   start_time(P,S,T),
   capacity(day, CU, CUop, Delay, Q),
   T+D > Delay+Q.


%DEFINE
    %%% -- a packet is satisfied if every contained service is provided
    sat_pkt(Pat, Pkt_ID)   :- provides(_, _, Pat, Srv) : contains_service(Pat, Pkt_ID, Srv); schedule(Pat, (Pkt_ID, _), day).
    unsat_pkt(Pat, Pkt_ID) :- schedule(Pat, (Pkt_ID, _), day), not sat_pkt(Pat, Pkt_ID).


%CONSTRAINT
    %%% -- Forbid the presence of a provided service that is not part of any satisfied packet (All the provided must be useful to satisfy at least one packet)
:- provides(_, _, Pat, Srv), not provides(Pat, Srv, Pat, Srv), #count{sat_pkt(PatX, Pkt_ID) : contains_service(PatX, Pkt_ID, Srv), PatX=Pat}=0.




#show start_time/3.
#show service/2.
#show precedes/4.
#show provides/4.

#show sat_pkt/2.
#show unsat_pkt/2.
