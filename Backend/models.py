from dataclasses import asdict, dataclass
from enum import StrEnum
import math
from typing import NamedTuple, Sequence


class Coordinate(NamedTuple):
    latitude: float
    longitude: float

    @classmethod
    def parse(cls, values: Sequence[float]) -> 'Coordinate':
        if len(values) != 2:
            raise ValueError('坐标格式错误')
        latitude, longitude = map(float, values)
        if not math.isfinite(latitude + longitude) or abs(latitude) > 90 or abs(longitude) > 180:
            raise ValueError('坐标超出范围')
        return cls(latitude, longitude)


class DeviceCommand(StrEnum):
    DEVICES = 'devices'
    CONNECT = 'connect'
    LOCATE = 'locate'
    START = 'start'
    PAUSE = 'pause'
    RESUME = 'resume'
    RESTART = 'restart'
    CLEAR = 'clear'
    STATUS = 'status'
    SHUTDOWN = 'shutdown'


class SessionState(StrEnum):
    DISCONNECTED = 'disconnected'
    CONNECTING = 'connecting'
    READY = 'ready'
    FIXED = 'fixed'
    RUNNING = 'running'
    PAUSED = 'paused'
    COMPLETED = 'completed'
    RECONNECTING = 'reconnecting'
    INTERRUPTED = 'interrupted'


@dataclass(frozen=True)
class Capabilities:
    canConnect: bool = True
    canStart: bool = False
    canLocate: bool = False
    canPause: bool = False
    canResume: bool = False
    canRestart: bool = False
    canClear: bool = False
    canChooseTrack: bool = True
    canEditPace: bool = True
    needsWakeLock: bool = False


@dataclass(frozen=True)
class SessionSnapshot:
    state: SessionState
    capabilities: Capabilities
    meters: float
    total: float
    pace: float | None
    position: Coordinate | None
    reconnects: int
    hasRoute: bool

    def to_wire(self) -> dict:
        result = asdict(self)
        result['position'] = self.position._asdict() if self.position else None
        return result
