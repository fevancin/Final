%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% SP part %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%DEF
    %%% -- CONTIENE PRESTAZIONE:    predicato utile per alleggerire la notazione, determina se un pacchetto (istanza) 
    %                               contiene una certa prestazione
contains_service(Pat, (Prot, It, Pkt), Srv) :- packet_type(Pat, Prot, It, Pkt, Type), service_in_packet(Type, Srv).

    %%% -- service is the basic element to be assigned to a time slot
service(Pat, Srv, Day) :- schedule(Pat, (Pkt_ID, _), Day), contains_service(Pat, Pkt_ID, Srv), horizon(Day).

%%%%%% -- Shifted start of a care unit: create a fake service that precedes all the others assigned to that care unit
service(Res, CU, Day) :- capacity(Day, Res, CU, Start, _), Start>0.                                %Create
service(CU, Res, Day, Dur, 0)    :- service(Res, CU, Day), capacity(Day, Res, CU, Dur, _).         %Assign a Duration = Start
provides(Res, CU, Res, CU, Day)  :- service(Res, CU, Day), capacity(Day, Res, CU, _, _).           %Force the assignment of that CU 
start_time(Res, CU, Day, 0)      :- service(Res, CU, Day), capacity(Day, Res, CU, _, _).

time(0..Tmax) :- Tmax=#max{T : T=S+D, capacity(_,_,_,S,D)}.

%GENERATE
    %%% -- With more than one units of the same kind the SP must decide to which the service has to be assigned
    %       The assigned CU must be of the same type and unique.
1{provides(Res, CU, Pat, Srv, Day) : capacity(_, Res, CU, _, _)}1 :- service(Pat, Srv, Day). %%%% perché non va con service(Srv, Res, _, _) dentro?
:- provides(Res, CU, Pat, Srv, _), not service(Srv, Res, _, _), Pat!=Res, Srv!=CU.               %%%%
:- provides(Res, CU, _, _, Day), not capacity(Day, Res, CU, _, _).

1{start_time(Pat, Srv, Day, Start) : time(Start)}1 :- service(Pat, Srv, Day).

%DEF
    %%% -- Precedes: A service precedes the other if the end of the former is not after the start of the latter
precedes(P1, S1, Day, P2, S2, Day) :- start_time(P1, S1, Day, Start1), start_time(P2, S2, Day, Start2), 
                                service(S1, _, D1, _), not care_unit(P1), not capacity(_,P1,S1,_,_), %vale così se non è il delay fake
                                Start1 + D1 <= Start2.
precedes(Res, CU, Day, P, S, Day) :- start_time(Res, CU, Day, Start1), start_time(P, S, Day, Start2), 
                                service(CU, Res, Day, D1, _), %anche per la service speciale fake
                                Start1 + D1 <= Start2.


%Constraints
    %%% -- different services of the same patient cannot be deployed at the same time, 
    %      one precedes the other
:- not precedes(Pat, Srv1, Day, Pat, Srv2, Day), not precedes(Pat, Srv2, Day, Pat, Srv1, Day), Srv1!=Srv2, 
   service(Pat, Srv1, Day), service(Pat, Srv2, Day), not care_unit(Pat), not capacity(_,Pat,Srv1,_,_), not capacity(_,Pat,Srv2,_,_).
    %non vale per il nome della Risorsa per il delay! e.g. red,1 e red,2 NON SI PRECEDONO

    %%% NOTE: can be changed! --    The same Unit (machine) is in use for only one 
    %                               service of a patient, not for + services or pats 
    %                               at the same time    
    %%% case of >1 Units
:- not precedes(Pat1, Srv1, Day, Pat2, Srv2, Day), not precedes(Pat2, Srv2, Day, Pat1, Srv1, Day), 
   service(Srv1, Res, _, _), service(Srv2, Res, _, _),
   provides(Res, CU, Pat1, Srv1, Day), provides(Res, CU, Pat2, Srv2, Day), 
   Pat1!=Pat2, service(Pat1, Srv1, Day), service(Pat2, Srv2, Day).

:- not precedes(Pat1, Srv1, Day, Pat2, Srv2, Day), not precedes(Pat2, Srv2, Day, Pat1, Srv1, Day), 
   service(Srv1, Res, Day, _, _), service(Srv2, Res, _, _),  %serve adattato per la service fake del delay
   provides(Res, CU, Pat1, Srv1, Day), provides(Res, CU, Pat2, Srv2, Day), 
   Pat1!=Pat2, service(Pat1, Srv1, Day), service(Pat2, Srv2, Day).

:- not precedes(Pat1, Srv1, Day,  Pat2, Srv2, Day), not precedes(Pat2, Srv2, Day,  Pat1, Srv1, Day), 
   service(Srv1, Res, _, _), service(Srv2, Res, _, _), 
   provides(Res, CU, Pat1, Srv1, Day), provides(Res, CU, Pat2, Srv2, Day), 
   Srv1!=Srv2, service(Pat1, Srv1, Day), service(Pat2, Srv2, Day).

:- not precedes(Pat1, Srv1, Day,  Pat2, Srv2, Day), not precedes(Pat2, Srv2, Day,  Pat1, Srv1, Day), 
   service(Srv1, Res, Day, _, _), service(Srv2, Res, _, _), 
   provides(Res, CU, Pat1, Srv1, Day), provides(Res, CU, Pat2, Srv2, Day), 
   Srv1!=Srv2, service(Pat1, Srv1, Day), service(Pat2, Srv2, Day).

    %%% -- Irreflexivity
:- precedes(Pat1, Srv1, Day, Pat1, Srv1, Day).

    %%% -- Antisimmetry
:- precedes(Pat1, Srv1, Day, Pat1, Srv2, Day), 
   precedes(Pat2, Srv2, Day, Pat1, Srv1, Day).

    %%% -- Transitivity
:- precedes(Pat1, Srv1, Day, Pat2, Srv2, Day), 
   precedes(Pat2, Srv2, Day, Pat3, Srv3, Day), 
   not precedes(Pat1, Srv1, Day, Pat3, Srv3, Day).

    %%% -- CAPACITY CONSTRAINT: (Strengthened) --> The sum of the durations of services that precede a service S 
%                                                over a chain, plus the duration of S, cannot exceed capacity
%					                             allocated for that care unit U associated to S

:- service(P,S,Day), 
    service(S,Res,D,_), %non c'é bisogno per la speciale fake
    provides(Res,CU,P,S,Day), 
    start_time(P,S,Day,T),
    capacity(Day, Res, CU, Delay, Q),
    T+D > Delay+Q.

#show start_time/4.
#show service/3.
%#show precedes/6.
#show provides/5.

