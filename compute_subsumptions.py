import os
import sys
import json
import time
import argparse

######################## INITIAL FILE AND FOLDER SETUP #########################

# read the command line arguments
parser = argparse.ArgumentParser(description="Compute instance subsumptions")
parser.add_argument("--input", help="folder with the instance file", type=str)
parser.add_argument("-v", "--verbose", help="prints what is done", action="store_true")
args = parser.parse_args(sys.argv[1:])

# move the current working directory to the file location
os.chdir(os.path.dirname(__file__))

# read the configuration file
if not os.path.isfile(os.path.join("config", "generator.json")):
    raise FileNotFoundError("Configuration file not found")
with open(os.path.join("config", "file_names.json"), "r") as file:
    config = json.load(file)

# check the existence of the instance folder
if not os.path.isdir(args.input):
    raise FileNotFoundError("Instance folder not found")

########################### MATCHING SEARCH FUNCTION ###########################

def custom_count(value, maxs):
    """Passing a list of integers, this function returns the next value in the
    counting sequence, treating each element as a digit. The maxs list give the
    maximum value (exclusive) for each digit, after that there is a remainder."""
    index = 0
    while index < len(value):
        value[index] += 1
        if value[index] < maxs[index]:
            return value
        value[index] = 0
        index += 1
    return None

def is_contained(small_day, big_day):
    """Function that search a match between two set of [start-duration] intervals.
    Each one of the first group must be contained in one of the second group without
    intersecting eachother. Some optimization are implemented in order to give
    a better performance when is not necessary to solve the full problem."""

    # trivial cases
    if len(small_day) == 0:
        return True
    if len(big_day) == 0:
        return False
    
    # check if the operator aer the same; useful if the schedule is periodic
    if len(small_day) == len(big_day):
        are_days_equal = True
        for operator, other_operator in zip(small_day.values(), big_day.values()):
            if operator["start"] != other_operator["start"] or operator["duration"] != other_operator["duration"]:
                are_days_equal = False
                break
        if are_days_equal:
            return True

    # dictionary that contain all the possible choices for the match
    possible_choices = dict()

    for small_operator_name, small_operator in small_day.items():
        possible_choices[small_operator_name] = list()
        for big_operator_name, big_operator in big_day.items():

            # add to the domain all big_operators that can contain the small one
            if small_operator["start"] >= big_operator["start"] and small_operator["start"] + small_operator["duration"] <= big_operator["start"] + big_operator["duration"]:
                possible_choices[small_operator_name].append(big_operator_name)
        
        # if a domain is empty, no match is possible
        if len(possible_choices[small_operator_name]) == 0:
            return False
        
    # list of all the small_operator that intersect
    incompatibility = list()

    for small_operator_name, small_operator in small_day.items():
        for other_small_operator_name, other_small_operator in small_day.items():

            # no self checks
            if other_small_operator_name == small_operator_name:
                continue

            # add the couple if the two operator intersect
            if small_operator["start"] <= other_small_operator["start"] and small_operator["start"] + small_operator["duration"] > other_small_operator["start"]:
                incompatibility.append((small_operator_name, other_small_operator_name))

    # if there are no conflicts, every match is a good one
    if len(incompatibility) == 0:
        return True
    
    # if a small operator have no conflicts it can be omitted, as every of its choiches is valid
    for small_operator_name in small_day.keys():
        is_present = False
        for couple in incompatibility:
            if small_operator_name == couple[0] or small_operator_name == couple[1]:
                is_present = True
                break
        if not is_present:
            del possible_choices[small_operator_name]
    
    names = list()
    value = list()
    maxs = list()
    for small_operator_name, domain in possible_choices.items():
        names.append(small_operator_name)
        value.append(0)
        maxs.append(len(domain))
    
    # enumerate all the assignable choices
    while value is not None:

        # test for overlaps in small operators that have chosen the same big operator
        is_valid_assignment = True
        for index in range(len(value) - 1):
            name = names[index]

            for other_index in range(index + 1, len(value)):
                other_name = names[other_index]

                if possible_choices[name][value[index]] == possible_choices[other_name][value[other_index]]:
                    if (name, other_name) in incompatibility or (other_name, name) in incompatibility:
                        is_valid_assignment = False
                        break
                if not is_valid_assignment:
                    break
        
        # if no overlaps is found the assignment is valid
        if is_valid_assignment:
            return True

        value = custom_count(value, maxs)

    return False

##################################### MAIN #####################################

if args.verbose:
    start_time = time.perf_counter()

# read the current instance file
input_file_name = os.path.join(args.input, config["instance_file_name"])
if not os.path.isfile(input_file_name):
    raise FileNotFoundError(f"Instance file {input_file_name} not found")
with open(input_file_name, "r") as file:
    mashp_input = json.load(file)

# take only the needed operator data
resources = mashp_input["resources"]
capacity = mashp_input["capacity"]
daily_capacity = mashp_input["daily_capacity"]
del mashp_input

# compute subsumptions for each separate care unit on the current instance
subsumptions = dict()
for care_unit_name in resources:
    subsumptions[care_unit_name] = dict()
    for day_name, day in daily_capacity.items():

        # all the days that can be contained in the current one
        smaller_days = set()

        for other_day_name, other_day in daily_capacity.items():

            # no reflexive checks (they are implicitly defined)
            if other_day_name == day_name:
                continue
            # impossible match if the total duration is smaller
            if capacity[day_name][care_unit_name] < capacity[other_day_name][care_unit_name]:
                continue
            # jump to the next day if the current one is already known to be smaller
            if other_day_name in smaller_days:
                continue

            # add the subsumption if other_day is contained in day
            if is_contained(other_day[care_unit_name], day[care_unit_name]):
                smaller_days.add(other_day_name)

                # transitivity check for already processed days
                if other_day_name in subsumptions[care_unit_name]:
                    smaller_days.update(subsumptions[care_unit_name][other_day_name])
        
        # do not add empty lists in the output
        if len(smaller_days) > 0:
            subsumptions[care_unit_name][day_name] = sorted(smaller_days)

# write subsumptions to file
subsumptions_file_name = os.path.join(args.input, config["subsumptions_file_name"])
with open(subsumptions_file_name, "w") as file:
    json.dump(subsumptions, file, indent=4)

if args.verbose:
    elapsed_time = time.perf_counter() - start_time
    print(f"Subsumptions took {elapsed_time} seconds.")