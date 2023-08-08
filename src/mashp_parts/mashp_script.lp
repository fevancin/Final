
#script (python)

import glob
from clingo import Number, String, Function, parse_term
import subprocess
import os
import sys
import re
import json
from datetime import datetime

THIS_DIR_tmp  =   '/home/marco/Universita/Dottorato/Studi/Progetto NCDs Agenda/outpatientsMASHP/progetto'#os.path.dirname(os.path.abspath(inspect.getfile(inspect.currentframe())))
THIS_DIR_name =   'src'#THIS_DIR_tmp.split('<')[1]
THIS_DIR      =   os.path.join(THIS_DIR_tmp.split('<')[0], THIS_DIR_name)
PARENT_DIR    =   os.path.abspath(os.path.join(THIS_DIR, '..'))
TARGET_DIR    =   os.path.join(PARENT_DIR, 'target')
#print(os.path.dirname(os.path.realpath(sys.argv[0])))  #subprocess con pipe per ritornare lettura

sys.path.append(THIS_DIR)

split_pat_file_fix_sol = os.path.join(TARGET_DIR, 'fixed_sol.lp')

from mashp_tools import read_ASP, get_cur_dir, str_format_times_dict, get_result_values
from collect4cut import collect_info


def breakpoint():
    go=False
    while not go or go=='':
        with open("pass.txt") as p:
            go=p.read()
    with open("pass.txt", 'w') as p:
        p.write('')


def main_monolitico(prg):

    #%###################################################
    #%                 Master Problem                   #
    #%###################################################

    #%prendo il tempo di start della prima iterazione MP  
    nowM_start = datetime.now()
    #%current_time = nowM_start.strftime("%H:%M:%S")
    #%print("\n\nStart Time M1 =", current_time)

    #%avvio grounding e solving del problema com'e' in origine
    prg.ground([("base", [])])
    
    nowM_gr_stop = datetime.now()
    
    prg.solve()

    nowM_stop = datetime.now()
    #%current_time = nowM_stop.strftime("%H:%M:%S")
    #%print("Stop Time M1  =", current_time)

    #%al termine devo scrivere la soluzione nel file 'readable_sol.lp'
    #%e lo faccio con l'apposito script 
    cmd=['python', os.path.join(PARENT_DIR, 'format_master_plan.py')]
    process = subprocess.Popen(cmd)
    process.wait()

    with open(os.path.join(TARGET_DIR, 'time_info.json'), 'w') as time_info_file:
        json.dump({"Grounding Time" : str(nowM_gr_stop - nowM_start),
                   "Solving Time"   : str(nowM_stop    - nowM_gr_stop)}, time_info_file, indent=4)

    print("Durata = "+str(nowM_stop - nowM_start))


def main_iterativo(prg, settings):
    #%Getting horizon dimension from input file
    input_file=os.path.join(PARENT_DIR, "input", "mashp_input.lp")
    l_input = read_ASP(input_file)
    nh = None
    for f in l_input:
        #%find the horizon constant
        if 'nh=' in f:
            horizon_l=re.split('\=|\.', f)
            nh=int(horizon_l[-2])
            break

    #%print('\n*** nh = '+str(nh)+' ***\n')

    #%###################################################
    #%                 Master Problem                   #
    #%###################################################
    
    #%dizionari dei timestamp e dei risultati per controllare i tempi di solving
    timestamp_dict={}
    info_iter_sol_dict={}
    #%prendo il tempo di start della prima iterazione MP  
    nowM_start = datetime.now()
    #current_time = nowM_start.strftime("%H:%M:%S")
    #print("\n\nStart Time M1 =", current_time)

    solve_result=None
#IF multishot...
    if settings['model']=='multishot':

        tl_init=settings["first_iter_tl"]
        tl_incr=settings["iter_tl_incr"]

        #%avvio grounding e solving del problema com'e' in origine
        prg.ground([("base", [])])
        nowM_gr_stop = datetime.now()
        #prg.solve()
        with prg.solve(async_ = True, yield_ = False) as handle:
            optim = handle.wait(tl_init)
            #print(optim)
            if optim:
                print("OPTIMUM REACHED")
            else:
                print("NOT PROVEN OPTIMALITY")
    ##    solve_result=handle.get()
        nowM_stop = datetime.now()
        #current_time = nowM_stop.strftime("%H:%M:%S")
        #print("Stop Time M1  =", current_time)

#ELSE IF no_multishot...
    elif settings['model']=='no_multishot':
        #%avvio grounding e solving del problema com'e' in origine
        prg.ground([("base", [])])
        nowM_gr_stop = datetime.now()
        #%prg.solve()
        time_limit=0
        with open(os.path.join(THIS_DIR, "time_limit.json")) as tl_file:
            tl_d=json.load(tl_file)
            tl=int(tl_d["tl"])
        with prg.solve(async_ = True, yield_ = False) as handle:        
            optim = handle.wait(tl)
            if optim:
                print("OPTIMUM REACHED")
            else:
                print("NOT PROVEN OPTIMALITY")
    ###        solve_result=handle.get()
        nowM_stop = datetime.now()
        #current_time = nowM_stop.strftime("%H:%M:%S")
        #print("Stop Time M1  =", current_time)
	    
#END IF ELSE
	    
    #%al termine devo scrivere la soluzione nel file 'readable_sol.lp'
    #%e lo faccio con l'apposito script 
    cmd=['python', os.path.join(PARENT_DIR, 'format_master_plan.py')]
    process = subprocess.Popen(cmd)
    process.wait()


    #%###################################################
    #%                   Sub Problem                    #
    #%###################################################
    #%Nota che agisce anche se il Master e' diventato UNSAT.
    #%In questo modo aggiorno tutte le soluzioni giornaliere (che fa terminare il loop)
    #%MA potrebbe essere rimosso e fatto agire solo per sol. SAT.

#%IF multishot...
    #if settings['model']=='multishot':
        #%prendo il tempo di inizio di tutti i SP
    nowS_start = datetime.now()
        #current_time = nowS_start.strftime("%H:%M:%S")
        #print("Start Time S1 =", current_time)
#%END IF multishot

    #%terminato il solving devo avviare tutti i SP per ciascun giorno (nh)
    p_list=[]
    output_file_l=[]
    for i in range(1, nh+1):
        output_file=open(os.path.join(TARGET_DIR, 'daily_agenda{}.lp'.format(i)), 'w')
        output_file_l.append(output_file)
        if settings['sp_dl'] == 'yes':
            cmd = ['clingo-dl', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler.lp')]
        else:
            cmd = ['clingo', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler_no_dl.lp')]
        if settings['sp_obj'] == 'opt':
            cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_obj_func.lp'))
        elif settings['sp_obj'] == 'sat':
            cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_sat_constr.lp'))
        if settings['nogood'] == 'greedy': #solo nel caso greedy, non puo' rifiutare cose che ho assegnato all'iterazione percedente
            cmd.append(os.path.join(TARGET_DIR, 'nogood.lp'))
        if settings['split_patients'] == 'yes':
            if os.path.isfile(split_pat_file_fix_sol):
                cmd.append(split_pat_file_fix_sol)
        process = subprocess.Popen(cmd, stdout=output_file, stderr=output_file)
        if settings['parallelize_sp'] == 'no':
            process.wait()
        else:
            p_list.append(process)
    for process in p_list:
        process.wait()
    for output_file in output_file_l:
        output_file.close()

    #%prendo il tempo di terminazione di tutti i SP
    nowS_stop = datetime.now()
    #current_time = nowS_stop.strftime("%H:%M:%S")
    #print("Stop Time S1  =", current_time)

    iter_counter=1
    #%dopo la prima iterazione inserisco i tempi salvati nel dizionario apposito
    timestamp_dict[iter_counter]={'M_tot'      :    (nowM_start, nowM_stop), 
                                  'M_grounding':    (nowM_start, nowM_gr_stop),
                                  'M_solving'  :    (nowM_gr_stop, nowM_stop),
                                  'S_tot'      :    (nowS_start, nowS_stop)
                                  }

#%IF multishot...
    if settings['model']=='multishot':

        #salvo le info dei risultati della prima iterazione      
        search_file = glob.glob(os.path.join(TARGET_DIR, 'daily_agenda*.lp'))
        search_file = [f for f in search_file if not re.search('_p.\.lp', f)]
        #salvo la sol del master
        info_dict={'mp' : get_result_values(os.path.join(TARGET_DIR, 'sol.lp'))}
        #salvo le sol dei SP
        for fsp in search_file:
            info_dict['sp{}'.format(fsp.split('daily_agenda')[-1].split('.lp')[0])] = get_result_values(fsp)
        info_iter_sol_dict[iter_counter]=info_dict
        with open(os.path.join(TARGET_DIR, 'sol_info.json'), 'w') as sol_info_file: #lo faccio ad ogni iteraz. cosi' si puo' monitorare, ma posso farlo al termine
            json.dump(info_iter_sol_dict, sol_info_file, indent=4)

        #%########################################################################
        #%QUESTA VA TOLTA MI RACCOMANDO, e' SOLO PER PROVARE
        #%with open(os.path.join(TARGET_DIR, 'daily_agenda1.lp'), 'w') as cambio:
        #%    cambio.write('UNSATISFIABLE')
        #%#########################################################################

        #%Flag per evitare loop in caso sia insoddisfacibile già il MP all'inizio
        #%UNSAT=False
        #%with open(os.path.join(TARGET_DIR, 'readable_sol.lp'), 'r') as s_file:
        #%    line=s_file.readline()
        #%    while(line):
        #%        if 'UNSATISFIABLE' in line:
        #%            UNSAT=True
        #%            break
        #%        line=s_file.readline()    

        #%a questo punto devo raccogliere le info degli SP per generare i cut da aggiungere al MP
        cut_d = collect_info()
        #print('\n'+str(cut_d)+'\n')

        greedy_fixed=[] #per evitare di ripetere valori fissati gia' in precedenza
        #%finche' esistono agende giornaliere non ammissibili, itero aggiungendo clausole di no-good
        while cut_d: #% and not UNSAT:

            #%%%%%%%%%%%%
            #breakpoint() #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            #%%%%%%%%%%%%

            #%###################################################
            #%                 Master Problem                   #
            #%###################################################

            #%catturo il timestamp dell'inizio della seconda iterazione
            nowM_start = datetime.now()
            #current_time = nowM_start.strftime("%H:%M:%S")
            #print("Start Time M{} =".format(str(iter_counter)), current_time)

            #%check if timeout is reached
            if os.path.exists(os.path.join(PARENT_DIR, 'test', 'tmp_time_limit.json')):
                with open(os.path.join(PARENT_DIR, 'test', 'tmp_time_limit.json'), 'r') as tmp_tl_file:
                    tmp_tl_d=json.load(tmp_tl_file)

    # DEBUG #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%            
    #            with open(os.path.join(PARENT_DIR, 'debug.txt'), 'a+') as dbg:
    #                dbg.write(datetime.strftime(datetime.strptime(tmp_tl_d['end'], '%y-%m-%d %H:%M:%S'), '%y-%m-%d %H:%M:%S'))
    #                dbg.write('\t')
    #                dbg.write(datetime.strftime(nowM_start, '%y-%m-%d %H:%M:%S'))
    #                dbg.write('\n')
    #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
                if datetime.strptime(tmp_tl_d['end'], '%y-%m-%d %H:%M:%S')<=nowM_start:
                    break

            #%devo creare una lista di elementi da rendere ground all'interno del programma nogood
            #%che contiene le informazioni raccolte sul nogood da inserire, i.e. ogni termine della
            #%nuova clausola 
            add_ground=[]

            #MODELLO GREEDY
            if settings['nogood'] == 'greedy':
                with open(os.path.join(TARGET_DIR, 'nogood.lp'), 'a') as ng:
                    if iter_counter == 1: ng.write('greedy.\n')
                    index_printed=False
                    for day,l in cut_d.items():
                        #print("fisso soluzioni della data"+' '+str(day)+' '+str(l))
                        for t in l['sat']:
                            if not t in greedy_fixed:
                                add_ground.append(("greedy", [parse_term('sat'),parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(t[4])), Number(int(t[5]))]))
                                greedy_fixed.append(t)
                                if not index_printed:
                                    ng.write(f"%Iter: {iter_counter}\n")
                                    index_printed=True
                                ng.write("fix_schedule({},{},{},{},{},{}).\n".format(t[0], t[1], t[2], t[3], t[4], t[5]))
                        for t in l['unsat']:
                            add_ground.append(("greedy", [parse_term('unsat'),parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(t[4])), Number(int(t[5]))]))
                            if not index_printed:
                                ng.write(f"%Iter: {iter_counter}\n")
                                index_printed=True
                            ng.write("not_schedulable({},(({},{},{}),{}),{}).\n".format(t[0], t[1], t[2], t[3], t[4], t[5]))


            #%VERSIONE NAIVE
            if settings['nogood'] == 'naive':
                for day,l in cut_d.items():
                    print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(l))
                    for t in l:
                        add_ground.append(("nogood", [parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(t[4])), Number(int(t[5])), Number(iter_counter)]))
                        #%qui sto usando iter_counter come ID del gruppo di pazienti, potrebbe essere necessario diverso
                        #%qualora si trovassero piu' gruppi alla stessa iterazione


            #%VERSIONE UNSAT CORES singolo giorno (BASIC)
            elif settings['nogood'] == 'basic_unsat_core':
                gid=0
                for day,l in cut_d.items():
                    for grp in l:
                        print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(grp))
                        for t in grp:
                            add_ground.append(("nogood_cut", [parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(day)), Number(iter_counter), Number(gid)]))
                        gid+=1
            

            #%VERSIONE UNSAT CORES RIDOTTI singolo giorno [multipacchetti con nome] (NAIVE)   -- usa cut_d dei multipacket
            elif settings['nogood'] == 'multipacket_with_names1':
                for day,gd in cut_d.items():
                    for gid, mpkt_d in gd.items():
                        print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(gid))
                        for mpkt_id,pat_name in enumerate(mpkt_d):
                            mpkt_label = '_'.join(sorted(mpkt_d[pat_name]))
                            for srv in mpkt_d[pat_name]:
                                #print([pat_name, mpkt_label, srv, int(day), iter_counter, gid])
                                add_ground.append(("multipacket_nogood_with_names", [parse_term(pat_name), parse_term(mpkt_label), parse_term(srv), Number(int(day)), Number(int(iter_counter)), Number(int(gid))]))        


            #%VERSIONE UNSAT CORES COMBINAZIONE TUTTI I NOMI
            elif settings['nogood'] == 'multipacket_with_names2':
                for day,group_d in cut_d.items():
                    for gid, group_l in group_d.items():
                        for mpkt_id,mpkt in enumerate(group_l):
                            mpkt_label='_'.join(sorted(mpkt[1]))
                            for srv in mpkt[1]:
                                add_ground.append(("multipacket_nogood_with_names", [parse_term(mpkt[0]), 
                                                                                    parse_term(mpkt_label), 
                                                                                    #%int(mpkt_id), 
                                                                                    parse_term(srv), 
                                                                                    Number(int(day)), 
                                                                                    iter_counter, gid]))

            #%VERSIONE UNSAT CORES MULTIPACKETS : INSERIMENTO CORRETTO MA NON FUNZIONA ASP
            elif settings['nogood'] == 'multipacket_unsat_core':
                for day,gd in cut_d.items():
                    for gid, mpkt_d in gd.items():
                        print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(gid))
                        for mpkt_id,pat_name in enumerate(mpkt_d):
                            mpkt_label = '_'.join(sorted(mpkt_d[pat_name]))
                            for srv in mpkt_d[pat_name]:
                                #print([pat_name, mpkt_label, mpkt_id, srv, int(day), iter_counter, gid])
                                add_ground.append(("multipacket_nogood", [parse_term(mpkt_label), Number(int(mpkt_id)), parse_term(srv), Number(int(day)), Number(iter_counter), Number(gid)]))        
            
            print("ITER COUNTER = ",iter_counter)
            #%aggiungo gli elementi al programma
            #%e.g.
            #%prg.ground([("nogood", [parse_term("joeanthony"),parse_term("pi74"),3,1,3,132,4]),  %[paz, prot, iter, pacc, occ, giorno, gid]
            #%           ("nogood", [parse_term("gaelan"),parse_term("pi529"), 2,1,1,132,3])])
            
            #%if iter_counter>1:
            #%    prg.release_external(Function("q", [iter_counter-1]))
            #%prg.cleanup()
            nowM_gr_start = datetime.now()
            nowM_gr_stop = nowM_gr_start
            if add_ground:
            #%    prg.assign_external(Function("q", [iter_counter]), True)
                prg.ground(add_ground)
                #prg.ground([("base",[])])
                nowM_gr_stop = datetime.now()
            # prg.solve() #%no timeout
                try:
                    with prg.solve(async_ = True, yield_ = False) as handle:
                        optim = handle.wait(tl_init + tl_incr*iter_counter)
                        #print(optim)
                        if optim:
                            print("OPTIMUM REACHED")
                        else:
                            print("NOT PROVEN OPTIMALITY")
            ##            solve_result=handle.get()
                except:
                    print("terminazione")
            iter_counter+=1

            #%catturo il tempo di termine della seconda iterazione
            nowM_stop = datetime.now()
            #current_time = nowM_stop.strftime("%H:%M:%S")
            #print("Stop Time M{}  =".format(iter_counter), current_time)

            #%creo il file readable_sol.lp
            cmd=['python', os.path.join(PARENT_DIR, 'format_master_plan.py')]
            process = subprocess.Popen(cmd)
            process.wait()


            #%###################################################
            #%                    Sub Problem                   #
            #%###################################################
            #%Nota che agisce anche se il Master e' diventato UNSAT.
            #%In questo modo aggiorno tutte le soluzioni giornaliere (che fa terminare il loop)
            #%MA potrebbe essere rimosso e fatto agire solo per sol. SAT.

            #%catturo il timestamp dell'inizio della seconda iterazione
            nowS_start = datetime.now()
            #%current_time = nowS_start.strftime("%H:%M:%S")
            #%print("Start Time S{} =".format(iter_counter), current_time)

            #%terminato il solving devo avviare tutti i SP per ciascun giorno (nh)
            p_list=[]
            output_file_l=[]
            for i in range(1, nh+1):
                output_file=open(os.path.join(TARGET_DIR, 'daily_agenda{}.lp'.format(i)), 'w')
                output_file_l.append(output_file)
                if settings['sp_dl'] == 'yes':
                    cmd = ['clingo-dl', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler.lp')]
                else:
                    cmd = ['clingo', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler_no_dl.lp')] 
                if settings['sp_obj'] == 'opt':
                    cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_obj_func.lp'))   
                elif settings['sp_obj'] == 'sat':
                    cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_sat_constr.lp'))   
                if settings['nogood'] == 'greedy': #solo nel caso greedy, non puo' rifiutare cose che ho assegnato all'iterazione percedente
                    cmd.append(os.path.join(TARGET_DIR, 'nogood.lp'))
                if settings['split_patients'] == 'yes':
                    cmd.append(split_pat_file_fix_sol)
                process = subprocess.Popen(cmd, stdout=output_file, stderr=output_file)
                p_list.append(process)
            for process in p_list:
                process.wait()
            for output_file in output_file_l:
                output_file.close()

            #%prendo il tempo di terminazione di tutti i SP
            nowS_stop = datetime.now()
            #%current_time = nowS_stop.strftime("%H:%M:%S")
            #%print("Stop Time S{}  =".format(iter_counter), current_time)
            
            #%################################################################################################
            #%QUESTA VA TOLTA MI RACCOMANDO, e' SOLO PER PROVARE
            #%if iter_counter==2:
            #%    with open(os.path.join(TARGET_DIR, 'daily_agenda2.lp'), 'w') as cambio:
            #%        cambio.write('UNSATISFIABLE')
            #%################################################################################################

            #%a questo punto devo raccogliere le info degli SP per generare i cut da aggiungere al MP
            cut_d = collect_info()
            #%print('NUOVO TAGLIO:\n'+str(cut_d)+'\n')
            
            #%Devo terminare quando non ho scartati e la soluzione MP e' confermata dai SP
            if settings['nogood']=='greedy' and \
                all(sd[1]['unsat'] == []                           for sd in cut_d.items()) and \
                all(all(el in greedy_fixed for el in sd[1]['sat']) for sd in cut_d.items()):
                print("MASTER PLAN fully confirmed.\n")
                cut_d = {}

            #%dopo ogni iterazione inserisco i tempi salvati nel dizionario apposito
            timestamp_dict[iter_counter]={'M_tot'      :    (nowM_start, nowM_stop), 
                                      'M_grounding'    :    (nowM_start, nowM_gr_stop),
                                      'M_solving'      :    (nowM_gr_stop, nowM_stop),
                                      'S_tot'          :    (nowS_start, nowS_stop)
                                      }

            #%salvo le info dei risultati, ad ogni iterazione per multishot (append!)        
            search_file = glob.glob(os.path.join(TARGET_DIR, 'daily_agenda*.lp'))
            search_file = [f for f in search_file if not re.search('_p.\.lp', f)]
            #%salvo la sol del master
            info_dict={'mp' : get_result_values(os.path.join(TARGET_DIR, 'sol.lp'))}
            #%salvo le sol dei SP
            for fsp in search_file:
                info_dict['sp{}'.format(fsp.split('daily_agenda')[-1].split('.lp')[0])] = get_result_values(fsp)
            info_iter_sol_dict[iter_counter]=info_dict
            with open(os.path.join(TARGET_DIR, 'sol_info.json'), 'w') as sol_info_file: #lo faccio ad ogni iteraz. cosi' si puo' monitorare, ma posso farlo al termine
                json.dump(info_iter_sol_dict, fp=sol_info_file, indent=4)

        #%printo la durata di ciascuna iterazione e salvo il file dei tempi di grounding e solving
        #%for i in range(1,iter_counter+1):
        #%    print("Durata {} = ".format(i)+str(timestamp_dict[i]['S_tot'][1] - timestamp_dict[i]['M_tot'][0]))
        with open(os.path.join(PARENT_DIR, 'target', 'time_info.json'), 'w') as tinfo_file:
            json.dump(str_format_times_dict(timestamp_dict), tinfo_file, indent=4)
#%END IF multishot
#% IF NO_MULTISHOT
    if settings['model'] == 'no_multishot':
        complete_timestamp_list=[]   #una lista perche' non sa a che iterazione ci troviamo col no_multishot, lo sa solo just_mashp.py
        if os.path.isfile(os.path.join(PARENT_DIR, 'target', 'time_info.json')): 
            with open(os.path.join(PARENT_DIR, 'target', 'time_info.json'), 'r') as tinfo_file:
                complete_timestamp_list = json.load(tinfo_file)
        complete_timestamp_list.append(str_format_times_dict(timestamp_dict)[1])
        with open(os.path.join(PARENT_DIR, 'target', 'time_info.json'), 'w') as tinfo_file:
            json.dump(complete_timestamp_list, tinfo_file, indent=4)
#END IF NO_MULTISHOT

def main(prg):
    #%leggo i settings dal file json
    settings={}
    with open(os.path.join(THIS_DIR, 'settings.json')) as settings_file:
        settings=json.load(settings_file)
#%## IF multishot OR no_multishot
    if settings['model'] in ['multishot', 'no_multishot']:
        main_iterativo(prg, settings)
#%## ELSE monolitico...
    elif settings['model'] == 'monolithic':
    	main_monolitico(prg)
    
#end.
