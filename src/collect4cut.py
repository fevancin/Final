# -*- coding: utf-8 -*-

import glob
import json
from os import path
import os
import re
from itertools import product

THIS_DIR   =   path.dirname(__file__)
TARGET_DIR =   path.abspath(path.join(THIS_DIR, '..', 'target'))
INPUT_DIR  =   path.abspath(path.join(THIS_DIR, '..', 'input'))

import sys
sys.path.append(THIS_DIR)

from mashp_tools import read_ASP, output_to_ASP, grep_ASP, predicate_name_dict

def natural_sort(l):
    """func for natural sorting, considering the numbers in a string"""

    convert = lambda text: int(text) if text.isdigit() else text
    alphanum_key = lambda key: [convert(c) for c in re.split('([0-9]+)', key)]
    return sorted(l, key=alphanum_key)


def fixed_partial(SUBSOL_l):
    """
    Modify the mechanism into a greedy model, where from iteration to iteration 
    the admissible part is returned which is to be fixed and the rejected part 
    which is not to be reinserted on the same day.
    """

    sat_list   = []
    unsat_list = []
    day_sp_sol_dict={}
    for file, day in SUBSOL_l:
        ## Read the solution predicates from the solution
        _, _, _, sol_list   = output_to_ASP(file, target_pred='sat_pkt(')
        # Separate satisfied and unsatisfied packets
        sat_list   = []
        unsat_list = []
        for p in sol_list:
            if 'sat_pkt(' in p and not 'unsat_pkt(' in p:
                sat_list.append(p)
            elif 'unsat_pkt(' in p:
                unsat_list.append(p)

        # Collect the satisfied and unsatisfied packets for the day
        sat_pkts_of_day=[]
        for fact in sat_list:
            t = re.split('\(|,|\)', fact)
            t = [el for el in t if el!='']
            sat_pkts_of_day.append(t[1:-1])
        unsat_pkts_of_day=[]
        for fact in unsat_list:
            t = re.split('\(|,|\)', fact)
            t = [el for el in t if el!='']
            unsat_pkts_of_day.append(t[1:-1])
        
        #return those who are satisfied who can be fixed in greedy and those who are not satisfied
        day_sp_sol_dict[day]={'sat':sat_pkts_of_day, 'unsat':unsat_pkts_of_day}
    
    #compare the master's solution to define who to confirm and who not to confirm
    day_constraint_dict=naive_cut(SUBSOL_l)
    fix={}
    #rI accept the need for packages that are already fixed
    nec_sat_l=grep_ASP(path.join(TARGET_DIR, 'readable_sol.lp'), 'necessity_tot_satisfied_fix(')
    nec_sat_l = [[tpl[1][0]] + tpl[1][1].replace('(','').replace(')','').split(',') for tpl in nec_sat_l]
    #I create two groups: sat = SP-approved part of the Master Plan, unsat = rejected part
    for day in day_sp_sol_dict:
        day_fix={'sat':[], 'unsat':[]}
        for pk in day_constraint_dict[day]:
            if any(upk == pk[:4] for upk in day_sp_sol_dict[day]['unsat']):
                day_fix['unsat'].append(pk)
            else:
                #checking that the requirements of the package are all met before fixing it
                if pk[:-1] in nec_sat_l:
                    day_fix['sat'].append(pk)
                #else: temporarily not fixed
        fix[day]=day_fix
    return fix


def naive_cut(UNSAT_l):
    sol_l=read_ASP(path.join(TARGET_DIR, 'readable_sol.lp'))
    day_constraint_dict={}
    for file, day in UNSAT_l:
        pats_of_day=[]
        for fact in sol_l:
            t = re.split('\(|,|\)', fact)
            t = [el for el in t if el!='']
            if t[0]=='schedule' and t[-2]==str(day):
                pats_of_day.append(t[1:-1])
        day_constraint_dict[day]=pats_of_day
    return day_constraint_dict


def unsat_core_cut(UNSAT_l):
    """Restituisce un dizionario dell'unsat core ovvero lista di pacchetti nel formato [nome, protocollo, iterazione, pacchetto].
    Notare che e' il pacchetto istanziato del paziente.
    Si tratta di un dizionario con chiave il giorno, e valore la lista contenente possibilmente diverse liste di unsat cores,
    ovvero liste composte dai pacchetti che sono serviti piu' ciascuno di quelli non serviti.
    """
    
    sat_list   = []
    unsat_list = []
    day_constraint_dict={}
    for file, day in UNSAT_l:
        #lettura predicati della soluzione
        _, _, _, sol_list   = output_to_ASP(file, target_pred='sat_pkt(')
        #smisto i pacchetti soddisfatti e non in 2 liste
        sat_list   = []
        unsat_list = []
        for p in sol_list:
            if 'sat_pkt(' in p and not 'unsat_pkt(' in p:
                sat_list.append(p)
            elif 'unsat_pkt(' in p:
                unsat_list.append(p)
        #print(day)
        #print(sat_list)
        #print(unsat_list)
        
        #per ciascun giorno raccolgo la lista dei pacchetti soddisfatti e di quelli non soddisfatti
        # dove ogni elemento e' uno dei parametri interni del predicato 
        sat_pkts_of_day=[]
        for fact in sat_list:
            t = re.split('\(|,|\)', fact)
            t = [el for el in t if el!='']
            sat_pkts_of_day.append(t[1:-1])
        unsat_pkts_of_day=[]
        for fact in unsat_list:
            t = re.split('\(|,|\)', fact)
            t = [el for el in t if el!='']
            unsat_pkts_of_day.append(t[1:-1])
        
        #Il vincolo e' che tutti i soddisfacibili non ci stanno insieme a uno qualsiasi dei non soddisfacibili
        day_constraint_dict[day]=[]
        for unsat_pkt in unsat_pkts_of_day:
            day_constraint_dict[day].append(sat_pkts_of_day.copy()+[unsat_pkt])
        #    print('day {}: {}'.format(day,day_constraint_dict[day]))
    for l in day_constraint_dict.values(): #se almeno un unsat core e' presente restituisci, altrimenti e' vuoto
        if l!=[]:
            return day_constraint_dict
    else: return {}


def find_pkt_type(pkt, types_l):
    for pkt_type in types_l:
        if pkt == pkt_type[1][:4]:
            return pkt_type[1][4]
    return None

def find_srv_of_pkt_type(pkt_type, abs_pkts_l):
    if pkt_type!=None:
        for abs_pkt in abs_pkts_l:
            if pkt_type == abs_pkt[1][0]:
                return abs_pkt[1][1].replace('(', '').replace(')', '').split(';')
    return None


def find_res_of_srv(srv, prest_l):
    for p in prest_l:
        if srv == p[1][0]:
            return p[1][1]
    return None


def core_reduction(core:dict, unsat_key, prest_l:list):
    unsat_multipacket = core[unsat_key]
    min_core = {unsat_key : unsat_multipacket}
    old_min_core = {}
    #loop finche' il core non viene piu' aggiornato
    while min_core != old_min_core:
        old_min_core = min_core.copy()
        #cerco tutti i multipacchetti del core che condividono qualche risorsa con quelli del core minimo corrente
        # partendo dal core minimo che contiente solo il multipacchetto (paziente) non totalmente servito
        for name, mpkt in core.items():
            res_mpkt_list = [find_res_of_srv(p, prest_l) for p in mpkt]
            for cur_key, cur_mpkt in old_min_core.items():
                res_cur_mpkt_list = [find_res_of_srv(p, prest_l) for p in cur_mpkt]
                #se le liste dei multipacket del core generale e del minimo core corrente hanno elementi che
                # condividono una stessa risorsa aggiorno il minimo core corrente aggiungendo il multipacchetto
                if any(res in res_mpkt_list for res in res_cur_mpkt_list):
                    min_core[name]=mpkt
    return min_core


def  multipacket_cut(UNSAT_l):
    day_constraint_dict = unsat_core_cut(UNSAT_l)  #l'ultimo di ogni taglio e' il non servito del core; pacchetti istanza schedulati
    #print("TAGLI RACCOLTI: ",day_constraint_dict, '\n')
    pacc_astr_l      = grep_ASP(path.join(INPUT_DIR, 'mashp_input.lp'), predicate_name_dict['pacchetto_astratto'] + '(')  #servizi nel pacchetto
    tipo_pacchetto_l = grep_ASP(path.join(INPUT_DIR, 'mashp_input.lp'), predicate_name_dict['tipo_pacchetto'] + '(')      #da istanza a pacchetto astratto
    prest_l          = grep_ASP(path.join(INPUT_DIR, 'mashp_input.lp'), predicate_name_dict['prest'] + '(')               #risorsa consumata dalle prestazioni
    #print("RISORSE PREST: ", prest_l, '\n')

    day_constraint_srv_dict = {}
    for d,l in day_constraint_dict.items():
        day_constraint_srv_dict[d]={}
        for gid,core_l in enumerate(l):
            if not gid in day_constraint_srv_dict[d]:
                day_constraint_srv_dict[d][gid]={}
            for pkt_l in core_l:
                if not pkt_l[0] in day_constraint_srv_dict[d][gid]:   #giorno, gruppo_id, nome_paz : lista prestazioni = multipacchetto
                    day_constraint_srv_dict[d][gid][pkt_l[0]]=[]
                day_constraint_srv_dict[d][gid][pkt_l[0]]+=find_srv_of_pkt_type(find_pkt_type(pkt_l, tipo_pacchetto_l), pacc_astr_l)
                #collassamento doppioni
                day_constraint_srv_dict[d][gid][pkt_l[0]]=list(set(day_constraint_srv_dict[d][gid][pkt_l[0]]))
            #print(day_constraint_srv_dict[d][gid])
            #cerco i minimi core, escludendo da ciascuno i multipacchetti che sono indipendenti dalle cause di mancato servizio        
            day_constraint_srv_dict[d][gid] = core_reduction(day_constraint_srv_dict[d][gid], core_l[-1][0], prest_l) #core_l[-1][0] e' il paziente (multipkt)
                                                                                                                      #non (del tutto) soddisfatto del core 
                                                                                                                      # identificato dal giorno,gid
            #print(day_constraint_srv_dict[d][gid])
            #input()
    return day_constraint_srv_dict


def delete_overlapping(combination_l:list):
    new_comb_l=[]
    for l in combination_l:
        remove=False
        for i in range(len(l)-1):
            for j in range(i+1,len(l)):
                if l[i][0]==l[j][0] and any(prest in l[i][1] for prest in l[j][1]):
                    remove=True
                    break
            if remove:
                break
        if not remove:
            new_comb_l.append(l)
    return new_comb_l


def multipacket_with_names(UNSAT_l):
    day_constraint_srv_dict = multipacket_cut(UNSAT_l)  #ottengo i core ridotti {Giorno: {Gruppo: {nome_paz: [multi, pacchetto]}}}
    pat_name_l = grep_ASP(path.join(INPUT_DIR, 'mashp_input.lp'), predicate_name_dict['paziente'] + '(')  #predicato che definisce i pazienti
    pat_name_l = [t[1][0] for t in pat_name_l]

    #voglio ottenere tutte le possibili combinazioni di pazienti associate ai gruppi di multipacchetto
    #print(day_constraint_srv_dict)
    day_constraint_srv_dict_names={}
    for day, group_d in day_constraint_srv_dict.items():
        new_gid=0
        day_constraint_srv_dict_names[day]={}
        for gid, mpkt_d in group_d.items():
            mpkt_group_l=list(mpkt_d.values())
            combination_l=list(list(zip(element, mpkt_group_l)) for element in product(pat_name_l, repeat=len(mpkt_group_l)))
            #print(day,gid,'\n',combination_l)
            combination_l=delete_overlapping(combination_l)
            #print(day,gid,'\n',combination_l)
            for comb in combination_l:
                day_constraint_srv_dict_names[day][new_gid]=comb
                #for mpkt_t in comb:
                #    day_constraint_srv_dict_names[day][new_gid][mpkt_t[0]]=mpkt_t[1]
                new_gid+=1
        #print(day,'\n', day_constraint_srv_dict_names[day])
    return day_constraint_srv_dict_names
                

select_func_cut = { 'greedy'                    : fixed_partial,
                    'naive'                     : naive_cut,
                    'basic_unsat_core'          : unsat_core_cut,
                    'multipacket_with_names1'   : multipacket_with_names,
                    'multipacket_with_names2'   : multipacket_with_names,
                    'multipacket_unsat_core'    : multipacket_cut
                }

settings={}
with open(os.path.join(THIS_DIR, 'settings.json')) as settings_file:
    settings=json.load(settings_file)

FUNC_CUT=select_func_cut[settings['nogood']]


def collect_info(func=None, search_file=None):
    if search_file == None:
        search_file=glob.glob(path.join(TARGET_DIR, 'daily_agenda*.lp'))
    #for each solution file of the different SPs, I look for ineligible sols
    search_file = [f for f in search_file if not re.search('_p.\.lp', f)]
    if settings['nogood'] == 'greedy':
        files_l=natural_sort(search_file)
        days_l=[int(re.split('([0-9]+)', file.split("daily_agenda")[-1])[1]) for file in files_l]
        return fixed_partial(list(zip(files_l,days_l)))

    else:
        UNSAT_l=[]
        for daily_agenda in natural_sort(search_file):
            with open(daily_agenda, 'r') as da:
                #SAT=False
                lines=da.readlines()
                lines.reverse()
            for line in lines: 
                if 'Answer:' in line:
                    break
                
                if ('SATISFIABLE' in line or 'OPTIMUM FOUND' in line) and not 'UNSATISFIABLE' in line:
                    #SAT=True
                #    break
                    pass
                
                if 'UNSATISFIABLE' in line or 'unsat_pkt(' in line: #se non e' ammissibile o ci sono pacchetti non soddisfatti la aggiungo
                    UNSAT_l.append((daily_agenda, int(re.split('([0-9]+)', daily_agenda.split("daily_agenda")[-1])[1])))
                    break
                
                #else: print('file {} contains neither SATISFIABLE, nor UNSATISFIABLE keyword'.format(daily_agenda))
                            ##qui si potrebbe mettere un check se non e' stato trovato nulla e segnalare l'errore
        if func!=None:
            return func(UNSAT_l)
        return FUNC_CUT(UNSAT_l)

if __name__=="__main__":
    print(collect_info())
