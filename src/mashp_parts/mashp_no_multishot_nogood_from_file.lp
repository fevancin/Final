#program base.

%%% NOGOOD NAIVE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
grp(Day,Grp):-nogood(_, _, Day, Grp).
:- schedule(Pat, Pkt, Day) : nogood(Pat, Pkt, Day, Grp); 
    grp(Day, Grp),
    naive.

%%% NOGOOD UNSAT CORE BASIC %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
grp(Day,Iid,Gid):-nogood_cut(_, _, Day, Iid, Gid).
:- schedule(Pat, (Pkt_ID, _), Day) : nogood_cut(Pat, Pkt_ID, Day, Iid, Gid);
    grp(Day, Iid, Gid),
    basic.
    
%%% NOGOOD UNSAT CORE REDUCTED WITH NAMES --> MEMORY ERROR with all combinations %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
grp(Day,Iid,Gid):-nogood_cut(_, _, Day, Iid, Gid).
:- schedule_srv(Day, Pat, Srv) : multipacket_nogood_with_names(Pat, Srv, Day, Iid, Gid); 
    grp(Day,Iid,Gid),
    named_mpk.


%%% NOGOOD UNSAT CORE REDUCTED (with propagation) %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

multipacket_nogood(Multi, MID, Srv, SubDay, IID, GID) :- multipacket_nogood(Multi, MID, Srv, Day, IID, GID), horizon(SubDay),
                                                        day_resource_subsumes(Day, SubDay, Res):multipacket(Multi,SrvX), service(SrvX, Res, _, _).

mpkt_nogood(Multi, MID, Day, IID, GID) :- multipacket_nogood(Multi, MID, Srv, Day, IID, GID).
multipacket(Multi, Srv)                :- multipacket_nogood(Multi, MID, Srv, Day, IID, GID).
multipacket(S,S):-service(S,_,_,_).

%DEF
basic_nogood_bunch_id((D,IID,GID)) :- mpkt_nogood(_,_,D,IID,GID).

nogood_srv_link(ID, (Multi,MID), Pat, Srv) :- pat_nogood(ID, (Multi,MID), Pat),
                                              multipacket(Multi, Srv).

%DEVO TAGLIARE SOLUZIONI CHE NON RISPETTANO I NOGOOD
%creo i link possibili
%schedule_multipacket((D,IID,GID), (Multi,MID), Pat):-
%    mpkt_nogood(Multi,MID, D,IID,GID), patient(Pat), horizon(D),
%    schedule_srv(D,Pat,Srv) : multipacket(Multi,Srv).   


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



%generate selezione archi
{pat_nogood((D,IID,GID), (Multi,MID), Pat):schedule_multipacket((D,IID,GID), (Multi,MID), Pat)}1 :- mpkt_nogood(Multi,MID, D,It,GID).

% Pat non associato a nogood che condividono pacchetti 
:-  pat_nogood(ID, (Multi1,MID1), Pat), 
    pat_nogood(ID, (Multi2,MID2), Pat),
    Multi1!=Multi2,
    share_packet(Multi1,Multi2).

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
    basic_nogood_bunch_id((D,It,GID)),
    mpk.

%condivide pacchetto se hanno un pacchetto in comune
share_packet(M1, M2) :- multipacket(M1, R), multipacket(M2, R).


%#show pat_nogood/3.
%#show schedule_multipacket/3.
%#show mpkt_nogood/5.
%#show multipacket/2.
%#show multipacket_nogood/6.
%#show schedule_srv/3.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
