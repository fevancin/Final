import os
import sys
import json
import time
import random
import shutil
import argparse
import datetime

######################## INITIAL FILE AND FOLDER SETUP #########################

# read the command line arguments
parser = argparse.ArgumentParser(description="Generates problem instances")
parser.add_argument("--config", help="configuration file", type=str, metavar="FILE", default=os.path.join("config", "generator.json"))
parser.add_argument("-v", "--verbose", help="prints what is done", action="store_true")
args = parser.parse_args(sys.argv[1:])

# move the current working directory to the file location
os.chdir(os.path.dirname(__file__))

# check for the configuration files existence
if not os.path.isfile(args.config):
    raise FileNotFoundError("Configuration file not found")
if not os.path.isfile(os.path.join("config", "file_names.json")):
    raise FileNotFoundError("Configuration file not found")

# read the generator configuration
with open(args.config, "r") as file:
    config = json.load(file)
with open(os.path.join("config", "file_names.json"), "r") as file:
    temp_config = json.load(file)

# copy only the configuration needed from file_name.json
config["instances_folder"] = temp_config["instances_folder"]
config["instance_file_name"] = temp_config["instance_file_name"]
del temp_config

# create the main instances folder
if os.path.isdir(config["instances_folder"]):
    shutil.rmtree(config["instances_folder"])
os.mkdir(config["instances_folder"])
os.chdir(config["instances_folder"])

########################## GLOBAL ONE-TIME GENERATION ##########################

if args.verbose:
    start_time = time.perf_counter()

random.seed(config["seed"])

datecode = datetime.datetime.now().strftime("%a-%d-%b-%Y-%H-%M-%S")

# generate the resource list (all the care unit names)
resources = list()
for care_unit_index in range(config["care_unit"]["number"]):
    resources.append(f'{config["care_unit"]["prefix"]}{care_unit_index:02}')

# generate all operator data. global_capacity groups the durations by care unit
global_capacity = dict()
global_daily_capacity = dict()
for day_index in range(1, config["horizon"]["stop"] + 1):
    day_name = f'{config["horizon"]["prefix"]}{day_index}'

    global_capacity[day_name] = dict()
    global_daily_capacity[day_name] = dict()

    for care_unit_index in range(config["care_unit"]["number"]):
        care_unit_name = f'{config["care_unit"]["prefix"]}{care_unit_index:02}'

        global_capacity[day_name][care_unit_name] = 0
        global_daily_capacity[day_name][care_unit_name] = dict()

        operator_number = random.randint(config["care_unit"]["size"]["min"], config["care_unit"]["size"]["max"])
        for operator_index in range(operator_number):
            operator_name = f'{config["daily_capacity"]["prefix"]}{operator_index:02}'

            start = random.randint(config["daily_capacity"]["start"]["min"], config["daily_capacity"]["start"]["max"])
            duration = random.randint(config["daily_capacity"]["duration"]["min"], config["daily_capacity"]["duration"]["max"])
            
            global_capacity[day_name][care_unit_name] += duration
            global_daily_capacity[day_name][care_unit_name][operator_name] = {
                "start": start,
                "duration": duration
            }

# generate all services
services = dict()
for service_index in range(config["service"]["number"]):
    services[f'{config["service"]["prefix"]}{service_index:02}'] = {
        "careUnit": f'{config["care_unit"]["prefix"]}{random.randint(0, config["care_unit"]["number"] - 1):02}',
        "duration": random.randint(config["service"]["duration"]["min"], config["service"]["duration"]["max"]),
        "cost": random.randint(config["service"]["cost"]["min"], config["service"]["cost"]["max"])
    }

# generate all interdictions
interdiction = dict()
for service_index in range(config["service"]["number"]):
    service_name = f'{config["service"]["prefix"]}{service_index:02}'

    interdiction[service_name] = dict()
    for other_service_index in range(config["service"]["number"]):
        other_service_name = f'{config["service"]["prefix"]}{other_service_index:02}'

        if other_service_index == service_index or random.random() >= config["interdiction"]["probability"]:
            interdiction[service_name][other_service_name] = 0
        else:
            interdiction[service_name][other_service_name] = random.randint(config["interdiction"]["duration"]["min"], config["interdiction"]["duration"]["max"])

# generate all necessities
necessity = dict()
for service_index in range(config["service"]["number"]):
    service_name = f'{config["service"]["prefix"]}{service_index:02}'

    necessity[service_name] = dict()

    if random.random() >= config["necessity"]["probability"]:
        continue

    necessity_size = random.randint(config["necessity"]["size"]["min"], config["necessity"]["size"]["max"])
    for other_service_index in sorted(random.sample(range(config["service"]["number"]), necessity_size)):
        other_service_name = f'{config["service"]["prefix"]}{other_service_index:02}'
        
        if other_service_index == service_index:
            continue

        start = random.randint(config["necessity"]["start"]["min"], config["necessity"]["start"]["max"])
        duration = random.randint(config["necessity"]["duration"]["min"], config["necessity"]["duration"]["max"])
        necessity[service_name][other_service_name] = [
            start,
            start + duration
        ]

# generate all packets
abstract_packet = dict()
packet_index = 0
size = config["abstract_packet"]["size"]["min"]

while packet_index < config["abstract_packet"]["number"]:

    window = (config["abstract_packet"]["number"] - packet_index + 1) // 2
    for _ in range(window):

        service_indexes = random.sample(range(config["service"]["number"]), size)
        service_names = map(lambda s: f'{config["service"]["prefix"]}{s:02}', service_indexes)

        abstract_packet[f'{config["abstract_packet"]["prefix"]}{packet_index:02}'] = sorted(service_names)
        packet_index += 1

    if size + 1 <= config["abstract_packet"]["size"]["max"]:
        size += 1

# generate all patients
global_pat_request = dict()
protocol_index = 0

for patient_index in range(config["patient"]["number"]["stop"]):
    patient_name = f'{config["patient"]["prefix"]}{patient_index:02}'

    global_pat_request[patient_name] = dict()

    # generate protocols
    protocol_number = random.randint(config["protocol"]["number"]["min"], config["protocol"]["number"]["max"])
    for _ in range(protocol_number):
        protocol_name = f'{config["protocol"]["prefix"]}{protocol_index:02}'
        protocol_index += 1

        global_pat_request[patient_name][protocol_name] = dict()

        iteration_packets = list()
        iteration_size = random.randint(config["iteration"]["size"]["min"], config["iteration"]["size"]["max"])
        packet_indexes = random.sample(range(config["abstract_packet"]["number"]), iteration_size)
        
        min_start = 1000
        max_end = 0
        
        # generate the protocol iteration to be repeated, shifted, many times
        for iteration_packet_index in packet_indexes:

            start = random.randint(config["iteration"]["packet"]["start"]["min"], config["iteration"]["packet"]["start"]["max"])
            frequency = random.randint(config["iteration"]["packet"]["frequency"]["min"], config["iteration"]["packet"]["frequency"]["max"])
            tolerance = random.randint(config["iteration"]["packet"]["tolerance"]["min"], config["iteration"]["packet"]["tolerance"]["max"])
            times = random.randint(config["iteration"]["packet"]["times"]["min"], config["iteration"]["packet"]["times"]["max"])
            
            # every interval cannot overlap
            if tolerance >= frequency / 2:
                tolerance = frequency // 2 - 1
            
            iteration_packets.append({
                "packet_id": f'{config["abstract_packet"]["prefix"]}{iteration_packet_index:02}',
                "start_date": start,
                "freq": frequency,
                "since": "start_date",
                "tolerance": tolerance,
                "existence": [
                    start - tolerance,
                    start + frequency * times + tolerance
                ]
            })

            # record the min and max day, in order to avoid iteration overlaps
            if start < min_start:
                min_start = start
            if start + frequency * times + tolerance > max_end:
                max_end = start + frequency * times + tolerance

        # generation of every protocol iteration
        iteration_number = random.randint(config["iteration"]["number"]["min"], config["iteration"]["number"]["max"])
        iteration_initial_shift = random.randint(config["iteration"]["initial_shift"]["min"], config["iteration"]["initial_shift"]["max"])
        for iteration_index in range(iteration_number):
            global_pat_request[patient_name][protocol_name][f'{config["iteration"]["prefix"]}{iteration_index + 1}'] = [
                iteration_packets,
                iteration_initial_shift
            ]
            iteration_initial_shift += (max_end - min_start)

    # generate the patient priority
    priority = random.randint(config["patient"]["priority_weight"]["min"], config["patient"]["priority_weight"]["max"])
    global_pat_request[patient_name]["priority_weight"] = priority
    

##################################### MAIN #####################################

if args.verbose:
    instance_number = 0
    group_number = 0

# generate groups with different horizons (day numbers)
for horizon in range(config["horizon"]["start"], config["horizon"]["stop"] + 1, config["horizon"]["step"]):

    # create an empty folder for the current group (if it already exists, empty it)
    group_folder_name = f'{config["grouping_folder_prefix"]}{horizon}{config["grouping_folder_suffix"]}'
    if os.path.isdir(group_folder_name):
        shutil.rmtree(group_folder_name)
    os.mkdir(group_folder_name)
    os.chdir(group_folder_name)

    if args.verbose:
        group_number += 1

    # take only the first days from global_capacity and global_daily_capacity, reusing them overtime
    capacity = dict()
    daily_capacity = dict()
    for day_name in global_capacity.keys():
        if int(day_name) <= horizon:
            capacity[day_name] = global_capacity[day_name]
            daily_capacity[day_name] = global_daily_capacity[day_name]

    # generate instances with different patient number
    for patient_number in range(config["patient"]["number"]["start"], config["patient"]["number"]["stop"] + 1, config["patient"]["number"]["step"]):

        # create an empty folder for the current instance (if it already exists, empty it)
        instance_folder_name = f'{config["instance_folder_prefix"]}{patient_number}{config["instance_folder_suffix"]}'
        if os.path.isdir(instance_folder_name):
            shutil.rmtree(instance_folder_name)
        os.mkdir(instance_folder_name)

        # take only the first patients from global_pat_request, reusing them overtime
        pat_request = dict()
        for patient_name in global_pat_request.keys():
            if int(patient_name.split(config["patient"]["prefix"])[1]) < patient_number:
                pat_request[patient_name] = global_pat_request[patient_name]

        # write the current instance file
        file_name = os.path.join(instance_folder_name, config["instance_file_name"])
        with open(file_name, "w") as file:
            json.dump({
                "datecode": datecode,
                "horizon": horizon,
                "resources": resources,
                "capacity": capacity,
                "daily_capacity": daily_capacity,
                "services": services,
                "interdiction": interdiction,
                "necessity": necessity,
                "abstract_packet": abstract_packet,
                "pat_request": pat_request
            }, file, indent=4)
        
        if args.verbose:
            print(f"Created {os.path.join(group_folder_name, file_name)} with horizon = {horizon} and {patient_number} patients")
            instance_number += 1
    
    os.chdir("..")

if args.verbose:
    elapsed_time = time.perf_counter() - start_time
    print(f"Generated {instance_number} instances in {group_number} groups ({instance_number // group_number} per group). Taken {elapsed_time} seconds.")