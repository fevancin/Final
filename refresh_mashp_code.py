#refresh_mashp_code

import os


THIS_DIR  = os.path.dirname(os.path.abspath(__file__))
mashp_dir = os.path.join(THIS_DIR, 'src', 'mashp_parts')

logic_file          = None
program_nogood_file = None
nogood_from_f_file  = None
script_file         = None
SP_logic_file       = None
SP_logic_no_dl_file = None
sussunzione_file    = None


with open(os.path.join(mashp_dir, 'mashp_logic.lp')) as logic:
    logic_file = logic.readlines()

with open(os.path.join(mashp_dir, 'mashp_multishot_program_nogood.lp')) as nogood_multishot:
    program_nogood_file = nogood_multishot.readlines()

with open(os.path.join(mashp_dir, 'mashp_no_multishot_nogood_from_file.lp')) as nogood_no_multishot:
    nogood_from_f_file = nogood_no_multishot.readlines()

with open(os.path.join(mashp_dir, 'mashp_script.lp')) as script:
    script_file = script.readlines()
for i,l in enumerate(script_file.copy()):
    if "THIS_DIR_tmp='" in l.replace(' ', ''):
        #for Windows
        if '\\' in THIS_DIR:
            THIS_DIR = THIS_DIR.replace('\\', '\\\\')
        script_file[i] = "THIS_DIR_tmp  =   '"+THIS_DIR+"'\n"
        break

with open(os.path.join(mashp_dir, 'mashp_SP_logic.lp')) as SP_logic:
    SP_logic_file = SP_logic.readlines()

with open(os.path.join(mashp_dir, 'mashp_SP_logic_no_dl.lp')) as SP_logic_no_dl:
    SP_logic_no_dl_file = SP_logic_no_dl.readlines()

with open(os.path.join(mashp_dir, 'mashp_sussunzione.lp')) as sussunzione:
    sussunzione_file = sussunzione.readlines()

multishot        = logic_file + [''] + sussunzione_file + [''] + program_nogood_file + [''] + script_file
no_multishot     = logic_file + [''] + sussunzione_file + [''] + nogood_from_f_file  + [''] + script_file
monolithic_no_dl = logic_file + [''] + SP_logic_no_dl_file                           + [''] + script_file
monolithic_dl    = logic_file + [''] + SP_logic_file

with open(os.path.join(THIS_DIR, 'src', 'mashp_multishot.lp'), 'w') as multishot_fp:
    multishot_fp.writelines(multishot)
print('multishot')
with open(os.path.join(THIS_DIR, 'src', 'mashp_no_multishot.lp'), 'w') as no_multishot_fp:
    no_multishot_fp.writelines(no_multishot)
print('no_multishot')
with open(os.path.join(THIS_DIR, 'src', 'mashp_monolithic_no_dl.lp'), 'w') as monolithic_fp:
    monolithic_fp.writelines(monolithic_no_dl)
print('monolithic_no_dl')
with open(os.path.join(THIS_DIR, 'src', 'mashp_monolithic.lp'), 'w') as monolithic_fp:
    monolithic_fp.writelines(monolithic_dl)
print('monolithic_dl')

print('\ncompletato.\n')