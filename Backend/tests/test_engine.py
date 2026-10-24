from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from engine import Route, Profile, Cursor, distance

class EngineChecks(unittest.TestCase):
    def setUp(self):self.route=Route([[32,118],[32.001,118],[32.001,118.001]])
    def test_length_and_interpolation(self):
        self.assertGreater(self.route.total,200)
        point=self.route.at(distance(self.route.points[0],self.route.points[1])/2)
        self.assertAlmostEqual(point[0],32.0005)
        self.assertAlmostEqual(point[1],118)
        self.assertEqual(self.route.at(self.route.total),self.route.points[-1])
    def test_invalid_coordinates(self):
        for point in [[91,0],[0,181],[float('nan'),0],[float('inf'),0]]:
            with self.assertRaises(ValueError):Route([[0,0],point])
    def test_duplicate_points_and_dateline(self):
        r=Route([[0,0],[0,0],[0,0.001]])
        self.assertTrue(all(map(lambda n:abs(n)<1,r.at(1))))
        r=Route([[0,179.999],[0,-179.999]])
        self.assertLess(abs(abs(r.at(r.total/2)[1])-180),1e-6)
    def test_no_progress_without_ack(self):
        c=Cursor(self.route,Profile(360,15,seed=4))
        proposal=c.proposal(1)
        self.assertEqual(c.meters,0)
        c.commit(proposal)
        self.assertGreater(c.meters,0)
        previous=c.meters
        self.assertIsNone(c.proposal(10))
        self.assertEqual(c.meters,previous)
    def test_bounded_smooth_pace(self):
        p=Profile(360,15,seed=99)
        previous=p.at(0)
        for i in range(1,10000):
            value=p.at(i/100)
            self.assertLessEqual(abs(value-360),15)
            self.assertLess(abs(value-previous),0.03)
            previous=value
    def test_duration(self):
        r=Route([[0,0],[0,0.01]]); c=Cursor(r,Profile(360,0))
        for _ in range(360):c.commit(c.proposal(1))
        self.assertAlmostEqual(c.meters,1000,places=6)

if __name__=='__main__':unittest.main()
