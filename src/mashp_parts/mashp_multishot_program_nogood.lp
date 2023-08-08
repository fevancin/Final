#program base.

%%% GREEDY %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#program greedy(s, pat,   prot, iter, pkt,  occ,  d).
        fix_sol(s, pat, ((prot, iter, pkt), occ), d).
#show fix_sol/4.

:-     schedule(Pat, Pkt, D), fix_sol(unsat, Pat, Pkt, D).
:- not schedule(Pat, Pkt, D), fix_sol(sat,   Pat, Pkt, D).

%%% NOGOOD BASE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#program nogood(pat,     prot, iter, pkt,  occ,  d, gid).
unfeas_subproblem(pat, ((prot, iter, pkt), occ), d, gid).

:- schedule(Pat, Pkt, Day) : unfeas_subproblem(Pat, Pkt, Day, Grp); 
    Day=d, Grp=gid.

%#show unfeas_subproblem/7.

%%% NOGOOD UNSAT CORE NAIVE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#program nogood_cut(pat,  prot, iter, pkt,  day, iid, gid).
unfeas_subproblem(  pat, (prot, iter, pkt), day, iid, gid).

%unfeas_pkt(Pat, Type, Day, (Iid, Gid))   :- unfeas_subproblem(Pat, Prot, Iter, Pkt, Day, Iid, Gid), packet_type(Pat, Prot, Iter, Pkt, Type). %se sono dello stesso tpo per un paziente, collassano, giusto?
%unfeas_srv(Pat, Srv,  Day, Id)   :- unfeas_pkt(Pat, Type, Day, Id), service_in_packet(Type, Srv).

%contains_service(Pat, CP, It, Pkt, Srv) :- packet_type(Pat, CP, It, Pkt, Type), service_in_packet(Type, Srv).

%correspond_schedule(Pat, Prot, Iter, Pkt, Occ, Day, pat, prot, iter, pkt, day, (iid, gid)) :- 
%        occorrenza_pacchetto(Pat, Prot, Iter, Pkt, Occ),
%        contains_service(Pat, Prot, Iter, Pkt, Srv) : unfeas_srv(pat, Srv, day, (iid, gid)).


%unfeas_schedule(Pat, Prot, Iter, Pkt, Occ, Day, Iid, Gid) :- unfeas_subproblem(Pat, Prot, Iter, Pkt, Day, Iid, Gid);
%    occorrenza_pacchetto(Pat, Prot, Iter, Pkt, Occ), 
%    Day=d, Iid=iid, Gid=gid.

%day 3: [[['selena', 'pi536', '2', '1'], ['deeanne', 'pi860', '2', '0']]]

%:- schedule(selena,pi536,2,1,1,3), schedule(deeanne,pi860,2,0,2,3).
%:- schedule(derald,pi268,2,0,1,7), schedule(mairin,pi308,2,0,1,7), schedule(darcie,pi296,1,0,5,7).

:- schedule(Pat, (Pkt_ID, _), Day) : unfeas_subproblem(Pat, Pkt_ID, Day, Iid, Gid);
%    occorrenza_pacchetto(Pat, Prot, Iter, Pkt, Occ), 
    Day=day, Iid=iid, Gid=gid.


%:- schedule(Pat, Prot, Iter, Pkt, Occ, Day) : contains_service(Pat, Prot, Iter, Pkt, Srv), unfeas_srv(Pat, Srv, Day, Id); 
%    Day=day, Id=(iid, gid).
%#show unfeas_subproblem/7.


%%% NOGOOD UNSAT CORE REDUCTED WITH NAMES --> MEMORY ERROR with all combinations %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#program multipacket_nogood_with_names(p_name, multi, srv, day, iid, gid).
%multipacket(multi, srv).
unfeas_subp(p_name, srv, day, iid, gid).

%:- schedule_srv(Day, Pat, Srv) : unfeas_subp(Pat, Multi, Srv, Day, Iid, Gid).%;%, multipacket(Multi, Srv); 
    %Day=day, Iid=iid, Gid=gid.

:- schedule_srv(Day, Pat, Srv) : unfeas_subp(Pat, Srv, Day, Iid, Gid); 
    Day=day, Iid=iid, Gid=gid. %[1@100, Day,Iid,Gid]

% DEBUG %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%not_sat(Day, Iid, Gid) :- 
%    schedule_srv(Day, Pat, Srv) : unfeas_subp(Pat, Srv, Day, Iid, Gid); 
%    Day=day, Iid=iid, Gid=gid.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

#show unfeas_subp/5.


%%% NOGOOD UNSAT CORE REDUCTED !!TODO!! %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#program multipacket_nogood(multi, mid, srv, day, iid, gid).
unfeas_core(multi, mid, srv, day, iid, gid).

unfeas_core(Multi, MID, Srv, SubDay, IID, GID) :- unfeas_core(Multi, MID, Srv, Day, IID, GID), horizon(SubDay),
                                                        day_resource_subsumes(Day, SubDay, Res):multipacket(Multi,SrvX), service(SrvX, Res, _, _).

mpkt_nogood(Multi, MID, Day, IID, GID) :- unfeas_core(Multi, MID, Srv, Day, IID, GID).
multipacket(Multi, Srv)           :- unfeas_core(Multi, MID, Srv, Day, IID, GID).
multipacket(S,S):-service(S,_,_,_).


%DEF
basic_nogood_bunch_id((D,IID,GID)) :- mpkt_nogood(_,_,D,IID,GID).

nogood_srv_link(ID, (Multi,MID), Pat, Srv) :- pat_nogood(ID, (Multi,MID), Pat),
                                              multipacket(Multi, Srv).

%DEVO TAGLIARE SOLUZIONI CHE NON RISPETTANO I NOGOOD
%creo i link possibili
#external q(iid).
%schedule_multipacket((D,IID,GID), (Multi,MID), Pat):- %q(iid),
%    mpkt_nogood(Multi,MID, D,IID,GID), patient(Pat), horizon(D),
%    schedule_srv(D,Pat,Srv) : multipacket(Multi,Srv);
%   D=day, IID=iid, GID=gid.%, Multi=multi, MID=mid.

%schedule_multipacket((day,iid,gid), (multi,mid), Pat):- q(iid),
%    patient(Pat),
%    schedule_srv(day,Pat,Srv) : multipacket(multi,Srv).
%   D=day, IID=iid, GID=gid.%, Multi=multi, MID=mid.


%schedule_multipacket((D,IID,GID), (Multi,MID), Pat):-
%    mpkt_nogood(Multi,MID, D,IID,GID), patient(Pat), horizon(D),
%    schedule_srv(D,Pat,Srv) : multipacket(Multi,Srv), 
%    D=day, IID=iid, GID=gid.%, Multi=multi.%, MID=mid.

%%%AGGIUNTO
%DEF: schedula una prestazione che richiede stessa risorsa ma in quantità maggiore
schedule_GE_srv(D,Pat,Srv_GE,Srv_LE) :- schedule_srv(D,Pat,Srv_GE),
                                        service(Srv_GE, Res, Dur_GE, _), 
                                        service(Srv_LE, Res, Dur_LE, _),
                                        Dur_GE>=Dur_LE.

%qui potrei dire che hanno stessa risorsa e durata > : service(Srv, Res)
%Quindi: esiste un possibile collegamento tra un multipacket nogood (di un certo gruppo)
% e un paziente se questo schedula nel giorno di validità del nogood tutti servizi di durata
% maggiore o uguale a ciascuno di quelli del multipacket nogood, a parità di risorsa richiesta
schedule_multipacket((D,IID,GID), (Multi,MID), Pat):-
    mpkt_nogood(Multi,MID, D,IID,GID), patient(Pat), horizon(D),
    schedule_GE_srv(D,Pat,Srv_GE, Srv_LE) : multipacket(Multi,Srv_LE).
%%% FINE AGGIUNTO


%generate selezione archi
{pat_nogood((D,IID,GID), (Multi,MID), Pat):schedule_multipacket((D,IID,GID), (Multi,MID), Pat)}1 :- mpkt_nogood(Multi,MID, D,It,GID).

% Pat non associato a nogood che condividono pacchetti 
:-  pat_nogood(ID, (Multi1,MID1), Pat), 
    pat_nogood(ID, (Multi2,MID2), Pat),
    Multi1!=Multi2,
    condivide_pacchetto(Multi1,Multi2).

%AUX DEF
linked_nogood(ID, NG) :- pat_nogood(ID, NG, Pat). 
linked_pat(ID, Pat)   :- pat_nogood(ID, NG, Pat).
linked_pat_srv(ID, Pat,Srv) :- pat_nogood(ID, (Multi,MID), Pat), multipacket(Multi, Srv).

%Non posso avere un nogood non collegato, se c'é un paziente che ha i servizi del nogood non associati a nessuno
:- mpkt_nogood(Multi, MID, D,It,GID),
    not linked_nogood((D,It,GID), (Multi,MID)),
    schedule_multipacket((D,It,GID), (Multi,MID), Pat),
    not linked_pat_srv((D,It,GID), Pat, Srv) : multipacket(Multi, Srv).

%Non ammetto soluzioni che associano tutti i nogood
:- linked_nogood((D,It,GID), (Multi,MID)):mpkt_nogood(Multi,MID, D,It,GID); 
    basic_nogood_bunch_id((D,It,GID)).

%condivide pacchetto se hanno un pacchetto in comune
condivide_pacchetto(M1, M2) :- multipacket(M1, R), multipacket(M2, R).


%#show pat_nogood/3.
%#show schedule_multipacket/3.
%#show mpkt_nogood/5.
%#show multipacket/2.
%#show unfeas_core/6.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

