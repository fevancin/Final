%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% SP part %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%DEF
    %%% -- CONTIENE PRESTAZIONE:    predicato utile per alleggerire la notazione, determina se un pacchetto (istanza) 
    %                               contiene una certa prestazione
contains_service(Pat, (Prot, It, Pkt), Srv) :- packet_type(Pat, Prot, It, Pkt, Type), service_in_packet(Type, Srv).

    %%% -- service is the basic element to be assigned to a time slot
service(Pat, Srv, Day) :- schedule(Pat, (Pkt_ID, _), Day), contains_service(Pat, Pkt_ID, Srv), horizon(Day).


%GENERATE
    %%% -- With more than one units of the same kind the SP must decide to which the service has to be assigned
    %       The assigned CUop must be of the same type and unique.
1{provides(CU, CUop, Pat, Srv, Day) : capacity(Day, CU, CUop, _, _), service(Srv, CU, _, _)}1 :- service(Pat, Srv, Day), not provides(Pat, Srv, Pat, Srv, Day).

    %%% -- for each couple of services, 1 can precede 2, or not if they are parallel
{precedes((Pat1, Srv1), (Pat2, Srv2), Day)} :- service(Pat1, Srv1, Day), provides(_, _, Pat1, Srv1, Day), service(Pat2, Srv2, Day), provides(_, _, Pat2, Srv2, Day).

    %%% -- Assigning a time with dl: Start1 + Dur1 <= Start2 if 1 precedes 2
&diff { (Pat1,Srv1,Day) - (Pat2,Srv2,Day) } <= -Dur1 :- precedes((Pat1,Srv1),(Pat2,Srv2), Day), service(Srv1, _, Dur1, _).

%CONSTRAINTS
    %%% -- different services of the same patient cannot be deployed at the same time, 
    %      one precedes the other
:- not precedes((Pat, Srv1), (Pat, Srv2), Day), not precedes((Pat, Srv2), (Pat, Srv1), Day), Srv1!=Srv2, 
   service(Pat, Srv1, Day), service(Pat, Srv2, Day), 
   provides(Res1, CUop1, Pat, Srv1, Day), provides(Res2, CUop2, Pat, Srv2, Day), 
   Pat!=Res1, Srv1!=CUop1, Pat!=Res2, Srv2!=CUop2.  %devo escludere il caso che si tratti di Pat=Unit e Srv=Operatore, ovvero la chiusura iniziale, il blocco fake

    %%% NOTE: can be changed! --    The same Unit (machine) is in use for only one 
    %                               service of a patient, not for + services or pats 
    %                               at the same time    
    %%% case of >1 Units
:- not precedes((Pat1, Srv1), (Pat2, Srv2), Day), not precedes((Pat2, Srv2), (Pat1, Srv1), Day), 
   service(Srv1, CU, _, _), service(Srv2, CU, _, _),
   provides(CU, CUop, Pat1, Srv1, Day), provides(CU, CUop, Pat2, Srv2, Day), 
   Pat1!=Pat2, service(Pat1, Srv1, Day), service(Pat2, Srv2, Day).

:- not precedes((Pat1, Srv1), (Pat2, Srv2), Day), not precedes((Pat2, Srv2), (Pat1, Srv1), Day), 
   service(Srv1, CU, _, _), service(Srv2, CU, _, _), 
   provides(CU, CUop, Pat1, Srv1, Day), provides(CU, CUop, Pat2, Srv2, Day), 
   Srv1!=Srv2, service(Pat1, Srv1, Day), service(Pat2, Srv2, Day).

    %%% -- CAPACITY CONSTRAINTS with time dl
%CAPACITY CONSTRAINTS with time dl
    %%% -- Start >= OpenT
&diff { 0-(Pat,Srv,Day) } <= - OpenT :- capacity(Day, CU, CUop, OpenT, Q),
                                   provides(CU, CUop, Pat, Srv, Day). 
    %%% -- Start + Dur =  End <= ClosT  = OpenT+Availability
&diff { (Pat,Srv,Day)-0 } <= -Dur+OpenT+Q :- capacity(Day, CU, CUop, OpenT, Q),
                                   provides(CU, CUop, Pat, Srv, Day), service(Srv, CU, Dur, _). 



#show start_time/4.
#show service/3.
%#show precedes/6.
#show provides/5.

