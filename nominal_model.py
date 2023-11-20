from pyomo.environ import *

#NOTE: ricorda che in questa versione non si usa il pacchetto che viene rimosso in automatico se un servizio non è
# servibile a priori
def create_instance_model(mashp_input, requests, day_name="1"):
    
    scheduled_services = dict()

    # solve each day separately
    day_requests = requests[day_name]
    scheduled_services[day_name] = list()

    # accumulators for each necessary index (no useless info)
    z_indexes = set()
    x_indexes = set()
    y_indexes = set()
    o_indexes_tmp = set()
    O = set()
    P = set()
    operator_translate = {}
    packet_indexes = set()
    packet_consistenco_indexes_tmp = set()
    dummy={
        'ckin_p'  : {},
        'ckout_p' : {},
        'ckin_o'  : {},
        'ckout_o' : {}
    }
    pat_srv = {}

    # find the maximum end time for each care unit
    max_times = dict()
    for care_unit_name, care_unit in mashp_input["daily_capacity"][day_name].items():
        max_time = 0
        for operator in care_unit.values():
            end_time = operator["start"] + operator["duration"]
            if end_time > max_time:
                max_time = end_time
        max_times[care_unit_name] = max_time

    #Indexes for z (i.e. S set)
    for patient_name, patient in day_requests.items():
        P.add(patient_name)
        pat_srv[patient_name] = set()
        for packet_name in patient["packets"]:
            is_packet_satisfiable = True
            temp_z_indexes = set()
            temp_o_indexes_tmp = set()
            for service_name in mashp_input["abstract_packet"][packet_name]:
                pat_srv[patient_name].add((patient_name, service_name))
                # is_service_satisfiable = False
                care_unit_name   = mashp_input["services"][service_name]["careUnit"]
                service_duration = mashp_input["services"][service_name]["duration"]
                for operator_name, operator in mashp_input["daily_capacity"][day_name][care_unit_name].items():
                    if service_duration <= operator["duration"]:
                        # is_service_satisfiable = True
                        op_name = f"{operator_name}__{care_unit_name}"
                        temp_o_indexes_tmp.add(((patient_name, service_name), op_name))
                        O.add(op_name)
                        operator_translate[op_name] = (operator_name, care_unit_name)
                # if not is_service_satisfiable:
                #     is_packet_satisfiable = False
                #     break
                temp_z_indexes.add((patient_name, service_name))
            if is_packet_satisfiable:
                z_indexes.update(temp_z_indexes)
                o_indexes_tmp.update(temp_o_indexes_tmp)
                packet_indexes.add((patient_name, packet_name))

    for packet_index in packet_indexes:
        for service_name in mashp_input["abstract_packet"][packet_index[1]]:
            packet_consistenco_indexes_tmp.add((packet_index[0], packet_index[1], service_name))
    
    z_indexes = sorted(z_indexes)
    o_indexes_tmp = sorted(o_indexes_tmp)
    packet_indexes = sorted(packet_indexes)
    packet_consistenco_indexes_tmp = sorted(packet_consistenco_indexes_tmp)


    #Indexes for x: links only for same patient
    for index1 in z_indexes:
        pat = index1[0]
        a_p = f"a_{pat}"   #dummy node check-in patient
        b_p = f"b_{pat}"   #dummy node check-ot patient
        x_indexes.add(((pat, a_p), index1))
        x_indexes.add((index1, (pat, b_p)))
        x_indexes.add(((pat, a_p), (pat, b_p)))

        dummy['ckin_p'][pat]  = (pat, a_p)
        dummy['ckout_p'][pat] = (pat, b_p)

        for index2 in z_indexes:
            if index1 != index2 and index1[0] == index2[0]:   #same patient
                x_indexes.add((index1, index2))    #(pat1,srv1) --> (pat2,srv2) and vice versa
    

    #Indexes for y
    for index1 in o_indexes_tmp:
        a_o = (index1[1], f"a_{index1[1]}")          #dummy node check-in (op,b_op)
        b_o = (index1[1], f"b_{index1[1]}")          #dummy node check-out (op,b_op)
        y_indexes.add((a_o, index1[0], index1[1]))   #links to dummy nodes 
        y_indexes.add((index1[0], b_o, index1[1]))    
        y_indexes.add((a_o, b_o, index1[1]))          #direct link check-in --> check-out (op,b_op)

        dummy["ckout_o"][index1[1]] = b_o
        dummy["ckin_o"][index1[1]]  = a_o

        for index2 in o_indexes_tmp:
            if index1 != index2 and index1[1] == index2[1]:    #same operator__cu can serve both
                y_indexes.add((index1[0], index2[0], index1[1]))    #(pat1,srv1) --> (pat2,srv2) at op_cu

    x_indexes = sorted(x_indexes)
    y_indexes = sorted(y_indexes)
    d_indexes = sorted(set((j,o) for (_,j,o) in y_indexes))

    x_prev_indexes = sorted(set(i[0] for i in x_indexes))
    x_next_indexes = sorted(set(j[1] for j in x_indexes))
    y_prev_indexes = sorted(set(i[0] for i in y_indexes))
    y_next_indexes = sorted(set(j[1] for j in y_indexes))
    #y_oper_indexes = sorted(set(o[2] for o in y_indexes))


    # solve subproblem problem
    model = ConcreteModel()

    #VAR INDEXES
    model.z_indexes = Set(initialize=z_indexes)
    model.x_indexes = Set(initialize=x_indexes)
    model.y_indexes = Set(initialize=y_indexes)
    model.d_indexes = Set(initialize=d_indexes)

    model.x_prev_indexes = Set(initialize=x_prev_indexes)
    model.x_next_indexes = Set(initialize=x_next_indexes)
    model.y_prev_indexes = Set(initialize=y_prev_indexes)
    model.y_next_indexes = Set(initialize=y_next_indexes)
    #model.y_oper_indexes = Set(initialize=y_oper_indexes)

    #other sets
    model.S = Set(initialize=z_indexes)
    model.P = Set(initialize=sorted(P))
    model.O = Set(initialize=sorted(O))
    model.a_p = dummy["ckin_p"]
    model.b_p = dummy["ckout_p"]
    model.a_o = dummy["ckin_o"]
    model.b_o = dummy["ckout_o"]
    model.S_pat_all = model.x_prev_indexes | model.x_next_indexes
    model.S_all = model.y_prev_indexes | model.S_pat_all | model.y_next_indexes

    model.t_indexes = model.S_pat_all | model.y_next_indexes

    model.bigT    = Param(initialize=max(max_times[cu] for cu in max_times))

    #VARIABLES
    model.z = Var(model.z_indexes, domain=Boolean)
    model.t = Var(model.t_indexes, domain=NonNegativeIntegers, bounds=(0, model.bigT))
    model.x = Var(model.x_indexes, domain=Boolean)
    model.y = Var(model.y_indexes, domain=Boolean)
    # model.d = Var(model.d_indexes, domain=NonNegativeIntegers, bounds=(0, model.bigT))
    #?   model.u = Var(model.x_indexes | model.y_indexes,    domain=Boolean)

    
    def get_param_operator(param):
        return {o : mashp_input["daily_capacity"][day_name][operator_translate[o][1]][operator_translate[o][0]][param] for o in O}

    def get_param_service(param):
        return {s : data[param] for s,data in mashp_input["services"].items()}

    start_time = get_param_operator("start")
    duration   = get_param_operator("duration")
    end_time   = {o : start_time[o]+duration[o] for o in O}

    delta = {i : get_param_service('duration')[i[1]] for i in z_indexes}
    rho   = {i : get_param_service('cost')[i[1]]     for i in z_indexes}

    # Data Parameters
    model.start_o = Param(model.O, initialize=start_time) # Starting service time of operators
    model.end_o   = Param(model.O, initialize=end_time)     # Ending service time of operators
    model.delta   = Param(model.S, initialize=delta)  # Duration of tasks
    model.rho     = Param(model.S, initialize=rho)  # Penalty for not performing tasks

    #model.pprint()
        
    return model

def create_nominal_model(mashp_input, requests):

    model = create_instance_model(mashp_input, requests)

    # Objective function
    def obj_rule(model):
        return sum(model.rho[i] * (1 - model.z[i]) for i in model.S)
    model.obj = Objective(rule=obj_rule, sense=minimize)

    # Constraints

    # Constraints (1) - Check-in task assignment for each patient
    def checkin_assignment_patient_rule(model, p):
        return sum(model.x[model.a_p[p], j] for j in model.x_next_indexes if j[0]==p) == 1
    model.checkin_assignment_patient = Constraint(model.P, rule=checkin_assignment_patient_rule)


    # Constraints (2) - Connect 'x' variables to 'z' variables for patients
    def connect_x_to_z_rule(model, pi,si, p):
        if pi == p:
            i=(pi,si)
            return sum(model.x[i, j] for j in model.x_next_indexes if j[0]==p and j!=i) == model.z[i]
        else:
            return Constraint.Skip
    model.connect_x_to_z = Constraint(model.S, model.P, rule=connect_x_to_z_rule)


    # Constraints (3) - flow conservation patient
    def flow_conservation_patient_rule(model, pi,si, p):
        if pi == p:
            i=(pi,si)
            return sum(model.x[i, j] for j in model.x_next_indexes if j[0]==p and j!=i) - \
                sum(model.x[j, i] for j in model.x_prev_indexes if j[0]==p and j!=i) == 0
        else:
            return Constraint.Skip
    model.flow_conservation_patient = Constraint(model.S, model.P, rule=flow_conservation_patient_rule)


    # Constraints (4) - Check-out task assignment for each patient
    def checkout_assignment_rule(model, p):
        return sum(model.x[i, model.b_p[p]] for i in model.x_prev_indexes if i[0]==p) == 1
    model.checkout_assignment = Constraint(model.P, rule=checkout_assignment_rule)


    # Constraints (5) - Patient check-in start time
    def patient_start_time_rule(model, pi,si, p):
        i=(pi,si)
        if pi==p:
            return model.t[model.a_p[p]] <= model.t[i]
        else:
            return Constraint.Skip
    model.patient_start_time = Constraint(model.S, model.P, rule=patient_start_time_rule)


    # Constraints (6) - task time sequence for patients
    def task_time_sequence_patient(model, pi,si, pj,sj, p):
        i=(pi,si)
        j=(pj,sj)
        if pi == p and pj == p and (i,j) in model.x_indexes:
            return  model.t[i] + model.delta[i] * model.x[i,j] <= model.t[j] + model.bigT * (1 - model.x[i,j])
        return Constraint.Skip
    model.task_time_sequence_patient = Constraint(model.S, model.x_next_indexes, model.P, rule=task_time_sequence_patient)


    # Constraints (7) - Patient task sequence
    def patient_task_sequence_rule(model, pi,si, pj,sj, p):
        i=(pi,si)
        j=(pj,sj)
        if i != j and pi==p and pj==p:
            return model.x[i, j] + model.x[j, i] <= 1
        else:
            return Constraint.Skip
    model.patient_task_sequence = Constraint(model.S, model.S, model.P, rule=patient_task_sequence_rule)


    # Constraints (8) - Check-in task assignment for each operator
    def checkin_assignment_operator_rule(model, o):
        return sum(model.y[model.a_o[o], j, o] for j in model.y_next_indexes if (model.a_o[o], j, o) in model.y_indexes) == 1
    model.checkin_assignment_operator = Constraint(model.O, rule=checkin_assignment_operator_rule)


    # Constraints (9) - Connect 'y' variables to 'z' variables for operators
    def connect_y_to_z_rule(model, pi,si):
        i=(pi,si)
        return sum(model.y[i, j, o] for j in model.y_next_indexes for o in model.O if (i,j,o) in model.y_indexes) == model.z[i]
    model.connect_y_to_z = Constraint(model.S, rule=connect_y_to_z_rule)


    # Constraints (10) - flow conservation for operators
    def flow_conservation_operator_rule(model, pi,si, o):
        i=(pi,si)
        if [idx for idx in model.y_indexes if (idx[0], idx[1]) == i and idx[4] == o]:
            return sum(model.y[i, j, o] for j in model.y_next_indexes if (i,j,o) in model.y_indexes) - sum(model.y[j, i, o] for j in model.y_prev_indexes if (j,i,o) in model.y_indexes)  == 0
        return Constraint.Skip
    model.flow_conservation_operator = Constraint(model.S, model.O, rule=flow_conservation_operator_rule)


    # Constraints (11) - Dummy sink node operator
    def dummy_sink_operator_rule(model, o):
        return sum(model.y[j, model.b_o[o], o] for j in model.y_prev_indexes if (j,model.b_o[o],o) in model.y_indexes) == 1
    model.dummy_sink_operator = Constraint(model.O, rule=dummy_sink_operator_rule)


    # Constraints (12) - Operator task start time
    def operator_start_time_rule(model, pi,si, o):
        i=(pi,si)
        return sum(model.start_o[o] * model.y[i, j, o] for j in model.y_next_indexes if (i, j, o) in model.y_indexes) <= model.t[i]
    model.operator_start_time = Constraint(model.S, model.O, rule=operator_start_time_rule)


    # Constraints (13) - task time sequence for operators
    def task_time_sequence_operator(model, pi,si, pj,sj, o):
        i=(pi,si)
        j=(pj,sj)
        if (i,j,o) in model.y_indexes:
            return  model.t[i] + model.delta[i] * model.y[i,j,o] <= model.t[j] + model.bigT * (1 - model.y[i,j,o])
        return Constraint.Skip
    model.task_time_sequence_operator = Constraint(model.S, model.y_next_indexes, model.O, rule=task_time_sequence_operator)


    # Constraints (14) - Operator task sequence
    def operator_task_sequence_rule(model, pi,si, pj,sj, o):
        i=(pi,si)
        j=(pj,sj)
        if (i, j, o) in model.y_indexes:
            return model.y[i, j, o] + model.y[j, i, o] <= 1
        return Constraint.Skip
    model.operator_task_sequence = Constraint(model.S, model.S, model.O, rule=operator_task_sequence_rule)


    # Constraints (15) - Operator task end time
    def operator_end_time_rule(model, o):
        return model.t[model.b_o[o]] <= model.end_o[o]
    model.operator_end_time = Constraint(model.O, rule=operator_end_time_rule)


    return model


def create_nominal_model_with_d_variables(mashp_input, requests):

    model = create_nominal_model(mashp_input, requests)

    #replacement of the task time sequence for operators constraint with the version using d
    model.task_time_sequence_operator.deactivate()
    
    #Create new variable d for the idle before task
    model.d = Var(model.d_indexes, domain=NonNegativeIntegers, bounds=(0, model.bigT))

    # Constraints (12) (replaced) - task time sequence for operators   NOTE: maybe an equality? no because of T
    def task_time_sequence_operator_with_d_rule(model, pi,si, pj,sj, o):
        i=(pi,si)
        j=(pj,sj)
        if (i,j,o) in model.y_indexes:
            return model.t[i] + model.delta[i] * model.y[i,j,o] + model.d[j,o] <= model.t[j] + model.bigT * (1 - model.y[i,j,o])
        return Constraint.Skip
    model.task_time_sequence_operator_with_d = Constraint(model.S, model.y_next_indexes, model.O, rule=task_time_sequence_operator_with_d_rule)


    # Constraint (16) - defining d ad the idle time before task
    def idle_definition_by_t_rule(model, pi,si, pj,sj, o):
        i=(pi,si)
        j=(pj,sj)
        if (i,j,o) in model.y_indexes:
            return model.t[i] + model.delta[i] * model.y[i,j,o] + model.d[j,o] >= model.t[j] - model.bigT * (1 - model.y[i,j,o])
        return Constraint.Skip
    model.idle_definition_by_t = Constraint(model.S, model.y_next_indexes, model.O, rule=idle_definition_by_t_rule)


    # Constraint (17) - relation between y and d variables
    def idle_link_with_y_rule(model, pi,si, o):
        i=(pi,si)
        if (i, o) in model.d_indexes:
            return model.d[i,o] <= model.bigT * sum(model.y[i, j, o] for j in model.y_next_indexes if (i,j,o) in model.y_indexes)
        return Constraint.Skip
    model.idle_link_with_y = Constraint(model.S, model.O, rule=idle_link_with_y_rule)

    
    # Constraint (18) - task time sequence for operators with idle
    def idle_sequencing_operator_rule(model, o):
        if [(i,j,o) for j in model.S for i in model.S if (i,j,o) in model.y_indexes]: #some variables y can be removed a priori if cannot be associated to o because of duration
            # print(o, sum(model.d[i, o] + model.delta[i] * model.y[i, j, o] for j in model.y_next_indexes for i in model.S if (i,j,o) in model.y_indexes), " <= ", model.end_o[o] - model.start_o[o])
            # input()
            return sum(model.d[i, o] + sum(model.delta[i] * model.y[i, j, o] for j in model.y_next_indexes if (i,j,o) in model.y_indexes) for i in model.S if any((i,j,o) in model.y_indexes for j in model.S)) <= model.end_o[o] - model.start_o[o]
        return Constraint.Skip
    model.task_time_sequence_operator_idle_chain = Constraint(model.O, rule=idle_sequencing_operator_rule)


    return model

def solve_with_milp_nominal(mashp_input, requests, mode):

    if mode == 'milp_nominal':
        model = create_nominal_model(mashp_input, requests)
    if mode == 'milp_nominal_with_d':
        model = create_nominal_model_with_d_variables(mashp_input, requests)
    
    # model.pprint()

    # Create a solver instance (choose an appropriate solver)
    solver = SolverFactory('glpk')

    # Solve the MILP model
    results = solver.solve(model)

    # Print the results
    if results.solver.termination_condition == TerminationCondition.optimal:
        print("Optimal solution found")
    else:
        print("Solver did not converge to an optimal solution")

    # Access variable values
    for i in model.S:
        print(f"z[{i}] = {model.z[i].value}")
    for i in model.x_indexes:
        print(f"x[{i}] = {model.x[i].value}")
    for i in model.y_indexes:
        print(f"y[{i}] = {model.y[i].value}")
    for i in model.t_indexes:
        print(f"t[{i}] = {model.t[i].value}")

    if mode == 'nominal_with_d':
        for i in model.d_indexes:
            print(f"d[{i}] = {model.d[i].value}")


    results.write()

    return None