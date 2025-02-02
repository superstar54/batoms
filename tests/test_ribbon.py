import bpy
from batoms.pdbparser import read_pdb
from batoms.batoms import Batoms
import os

path = os.path.dirname(os.path.abspath(__file__))


def test_ribbon():
    bpy.ops.batoms.delete()
    atoms = read_pdb(os.path.join(path, "datas/1ema.pdb"))  # 1ema, 1tim, 4hhb
    protein = Batoms("protein", from_ase=atoms)
    protein.ribbon.draw()
    sel1 = protein.selects.add("sel1", "sheet A-160-A-170")
    sel1.show = True
    sel1.model_style = 1
    bpy.ops.batoms.delete()
