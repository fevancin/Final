
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% SUSSUNZIONE SEMPLICE %%%%%%%%%%%%%%%%%%%%%%%%
%subsumes(DN, DM) :-
%    horizon(DN), horizon(DM),
%    day_worker_subsumed(DN,OP_ID,StartDM,StopDM):operator_shift(DM, OP_ID, StartDM, StopDM).

day_resource_subsumes(D, D, CU) :- horizon(D), resource(CU).
day_resource_subsumes(DN,DM,CU) :- horizon(DN), horizon(DM), resource(CU),
                                    day_worker_subsumed(DN,(CU,ID),StartDM,StopDM):operator_shift(DM, (CU,ID), StartDM, StopDM).

                                    

%sussunzione singolo operatore se uno è incluso temporalmente nell'altro
day_worker_subsumed(DN,(CU,ID2),StartDM,StopDM):-
    operator_shift(DM,(CU,ID1),StartDM,StopDM),
    operator_shift(DN,(CU,ID2),StartDN,StopDN),
    StartDN<=StartDM, StopDN>=StopDM.

%DEF
resource(CU):-capacity(_,CU,_,_,_).
operator_shift(DN,(CU,ID),StartDN,StartDN+Dur) :- capacity(DN,CU,ID,StartDN,Dur).
giorno(D):-capacity(D,_,_,_,_).
operatore(D,(CU,ID)):-operator_shift(D,(CU,ID),_,_).

#program sussunzione_matching.
%%%  SUSSUNZIONE GIORNATE  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%Dico che un giorno sussume un altro se lo sussume per tutte le risorse
%subsumes(DN, DM) :-
%    giorno(DN), giorno(DM),
%    day_resource_subsumes(DN,DM,CU):capacity(DM, CU, _, _, _).

%sussunzione singolo operatore se uno è incluso temporalmente nell'altro
day_worker_subsumed(DN,(CU,ID2),DM,(CU,ID1)):-
    operator_shift(DM,(CU,ID1),StartDM,StopDM),
    operator_shift(DN,(CU,ID2),StartDN,StopDN),
    StartDN<=StartDM, StopDN>=StopDM.

%SUSSUNZIONE RISORSE COME MATCHING
%gli archi sono rappresentati dalle sussunzioni tra operatori di due giorni diversi
arc(DN,DM,(DN,CU,IDN),(DM,CU,IDM)) :- day_worker_subsumed(DN,(CU,IDN),DM,(CU,IDM)), DM!=DN.
%simmetria sul grafo, notare che DN,DM e DM,DN rappresentano 2 grafi distinti, ciascuno per chi sussume chi
arc(DN,DM,VE,VS) :- arc(DN,DM,VS,VE), DM!=DN.

%devo selezionare degli archi come Match
{match(DN,DM,VS,VE)}1 :- DN!=DM, arc(DN,DM,VS,VE).
match(DN,DM,VE,VS) :- match(DN,DM,VS,VE).

% un match ha cardinalità <=1 dei nodi
:- match(DN,DM,VS,VE1), match(DN,DM,VS,VE2), VE1!=VE2.

%OTTIMALITA': assenza di cammino alternante aumentante --> MAX MATCH
%Base: alternato se c'é un arco vuoto
alternating_path(DN,DM,VS,VE):-
    arc(DN,DM,VS,VE),
    not match(DN,DM,VS,VE).

%ricorsione: alternato se alternato + arco in M + arco vuoto concatenato
alternating_path(DN,DM,VS,VE):-
    alternating_path(DN,DM,VS,VX),
    match(DN,DM,VX,VY),
    arc(DN,DM,VY,VE),
    not match(DN,DM,VY,VE).

%Vieto la presenza di cammino alternante aumentante i.e. che parte e termina in nodi liberi
:- alternating_path(DN,DM,VS,VE),
    not match(DN,DM,VS,VX):arc(DN,DM,VS,VX);
    not match(DN,DM,VY,VE):arc(DN,DM,VY,VE).

%Sussunzione risorse se la cardinalità del match è massima, ovvero pari alla cardinalità dei sussunti (DM)
day_resource_subsumes(D, D, CU) :- giorno(D), resource(CU).
day_resource_subsumes(DN,DM,CU) :- giorno(DN), giorno(DM), resource(CU),
                                    Card_match = #count{IDM : match(DN,DM,(DN,CU,_),(DM,CU,IDM))},
                                    DM_op=#count{ID:capacity(DM,CU,ID,_,_)},
                                    Card_match=DM_op.

%DEF
resource(CU):-capacity(_,CU,_,_,_).
operator_shift(DN,(CU,ID),StartDN,StartDN+Dur) :- capacity(DN,CU,ID,StartDN,Dur).
giorno(D):-capacity(D,_,_,_,_).
operatore(D,(CU,ID)):-operator_shift(D,(CU,ID),_,_).

%#show subsumes/2.
%#show day_resource_subsumes/3.
%#show day_worker_subsumed/4.
%#show match/4.
%#show alternating_path/4.
