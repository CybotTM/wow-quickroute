"""Regression tests for the non-executing, licensed source extractor."""
import tempfile
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import generate_destination_catalog as catalog


class CatalogueGeneratorTests(unittest.TestCase):
    def test_lua_functions_are_data_not_execution(self):
        tree = catalog.LuaDataParser('n(123,{coords={[84]={{30,40}}},OnUpdate=function() os.execute("touch /tmp/never-execute") end,g={i(3,{cost={{"c",2003,1}}})}})').value()
        self.assertIs(tree['OnUpdate'], catalog.UNKNOWN)
        self.assertIsNone(catalog.requirements(tree, {}))
        self.assertEqual([(84, .3, .4)], catalog.coords(tree))

    def test_inherited_prerequisite_groups_and_profession(self):
        parent = catalog.requirements({'sourceQuests': {1: 10, 2: 11}, 'sqreq': 1, 'requireSkill': 197}, {})
        child = catalog.requirements({'sourceQuests': {1: 20, 2: 21}}, parent)
        self.assertEqual([{'ids': [10, 11], 'required': 1}, {'ids': [20, 21], 'required': 2}], child['questGroups'])
        self.assertEqual(197, child['requireSkill'])
        self.assertIsNone(catalog.requirements({'r': 1}, {'r': 2}))
        parent = catalog.requirements({'minReputation': {1: 1, 2: 42000}}, {})
        child = catalog.requirements({'minReputation': {1: 2, 2: 9000}}, parent)
        self.assertEqual(2, len(child['reputationRules']))

    def test_unavailable_dynamic_and_invalid_coordinates_are_rejected(self):
        for restriction in ({'u': 1}, {'e': 24}, {'awp': 130000}, {'sourceQuests': catalog.UNKNOWN}, {'requireSkill': catalog.UNKNOWN}):
            self.assertIsNone(catalog.requirements(restriction, {}))
        self.assertEqual([], catalog.coords({'coords': {84: {1: {1: -1, 2: 40}, 2: {1: 40, 2: float('nan')}}}}))

    def test_generation_cost_semantics_roles_and_reproducibility(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            data = source / 'db/Standard/Categories'
            names = source / '.contrib/Parser/DATAS'
            output = source / 'addon/Data/Catalog.lua'
            data.mkdir(parents=True)
            names.mkdir(parents=True)
            output.parent.mkdir(parents=True)
            (source / 'LICENSE').write_text('MIT License\nCopyright Example\n')
            (names / 'names.lua').write_text('n(123, { -- Token Merchant\nq(20, { -- Known Quest\n')
            (data / 'Zones.lua').write_text('categories.Zones={h(-58,{g={n(123,{coords={[84]={{30,40}}},g={i(1,{cost={{"c",2003,2}}}),cu(777),i(2,{cost={{"i",3000,2}}})}})}}),q(20,{qgs={123},coords={[84]={{70,80}}}}),q(21,{coords={[85]={{50,60}}}}),q(22,{qgs={777},coords={[84]={{80,90}}}})}')
            def git_output(args, **_kwargs):
                return '' if 'status' in args else catalog.REVISION + '\n'
            with patch.object(catalog.subprocess, 'check_output', side_effect=git_output):
                catalog.generate(source, output)
                first = output.read_bytes()
                catalog.generate(source, output)
            self.assertEqual(first, output.read_bytes())
            generated = first.decode()
            self.assertIn('currencyID=2003', generated)
            self.assertNotIn('currencyID=777', generated)
            self.assertNotIn('currencyID=3000', generated)
            self.assertIn('role="giver"', generated)
            self.assertIn('role="reference"', generated)
            giver = next(line for line in generated.splitlines() if 'questID=20' in line and 'role="giver"' in line)
            reference = next(line for line in generated.splitlines() if 'questID=20' in line and 'role="reference"' in line)
            self.assertIn('x=0.3,y=0.4', giver)
            self.assertIn('x=0.7,y=0.8', reference)
            self.assertNotIn('npcID=777', generated, 'Quest coordinate must not synthesize a position for its giver')
            self.assertIn('Token Merchant', generated)
            self.assertTrue(output.with_suffix('.sources.txt').exists())
            self.assertTrue((output.parent.parent / 'Licenses/AllTheThings-MIT.txt').exists())

    def test_modified_source_checkout_is_rejected(self):
        with patch.object(catalog.subprocess, 'check_output', side_effect=[catalog.REVISION + '\n', ' M .contrib/Parser/DATAS/names.lua\n']):
            with self.assertRaisesRegex(ValueError, 'differ from the pinned revision'):
                catalog.generate(Path('/unused'), Path('/unused/output.lua'))


if __name__ == '__main__':
    unittest.main()
