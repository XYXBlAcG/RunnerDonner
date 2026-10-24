import bisect
import math
import random
from models import Coordinate

RADIUS = 6371008.8


def distance(a, b):
    x, y = math.radians(a[0]), math.radians(b[0])
    h = math.sin((y-x)/2)**2 + math.cos(x)*math.cos(y)*math.sin(math.radians(b[1]-a[1])/2)**2
    return 2*RADIUS*math.asin(math.sqrt(min(1, h)))


class Route:
    def __init__(self, points):
        if not 2 <= len(points) <= 20000:
            raise ValueError('轨迹必须包含 2～20000 个点')
        self.points = [Coordinate.parse(point) for point in points]
        self.cumulative = [0.0]
        for a,b in zip(self.points, self.points[1:]):
            self.cumulative.append(self.cumulative[-1]+distance(a,b))
        self.total = self.cumulative[-1]
        if self.total < 1:
            raise ValueError('轨迹总长度不足 1 米')

    def at(self, meters):
        if meters <= 0: return self.points[0]
        if meters >= self.total: return self.points[-1]
        meters = min(self.total,max(0,meters))
        i = min(len(self.points)-2, max(0,bisect.bisect_right(self.cumulative,meters)-1))
        span = self.cumulative[i+1]-self.cumulative[i]
        t = (meters-self.cumulative[i])/span if span else 1
        a,b=self.points[i:i+2]
        delta=(b[1]-a[1]+180)%360-180
        return Coordinate(a[0]+(b[0]-a[0])*t, (a[1]+delta*t+180)%360-180)


class Profile:
    def __init__(self, base, amplitude, seed=None):
        self.base=float(base)
        if not math.isfinite(self.base) or not 60<=self.base<=3600:
            raise ValueError('配速须在 1:00～60:00 之间')
        amplitude=float(amplitude)
        if not math.isfinite(amplitude) or not 0<=amplitude<=30:
            raise ValueError('波动幅度须在 0～30 秒之间')
        self.amplitude=min(amplitude,self.base-60,3600-self.base)
        self.random=random.Random(seed)
        self.targets=[self.base]

    def at(self, elapsed):
        pos=max(0,elapsed)/20
        i=int(pos)
        while len(self.targets)<i+2:
            self.targets.append(self.base+self.random.uniform(-self.amplitude,self.amplitude))
        t=pos-i;t=t*t*(3-2*t)
        return self.targets[i]*(1-t)+self.targets[i+1]*t


class Cursor:
    def __init__(self, route, profile):
        self.route=route;self.profile=profile;self.meters=0.;self.elapsed=0.;self.profile_epoch=0.

    @property
    def pace(self):
        return self.profile.at(self.elapsed-self.profile_epoch)

    def configure(self, profile):
        if self.profile.base == profile.base and self.profile.amplitude == profile.amplitude:
            return
        self.profile = profile
        self.profile_epoch = self.elapsed

    def proposal(self, dt):
        if not 0<=dt<=3:
            return None
        seconds=self.profile.at(self.elapsed-self.profile_epoch+dt/2)
        meters=min(self.route.total,self.meters+dt*1000/seconds)
        return meters,self.elapsed+dt,self.route.at(meters),seconds

    def commit(self, proposal):
        self.meters,self.elapsed=proposal[:2]
