import asyncio
import time
from collections.abc import Callable
from connection import DeviceConnection
from engine import Cursor, Profile, Route
from models import Capabilities, Coordinate, SessionSnapshot, SessionState


class Session:
    def __init__(self, connection=None, emit: Callable[[dict], None] | None = None):
        self.connection = connection if connection is not None else DeviceConnection()
        self.emit = emit if emit is not None else lambda payload: None
        self.udid = None
        self.state = SessionState.DISCONNECTED
        self.cursor = None
        self.last_point = None
        self.reconnects = 0
        self.suspended_state = SessionState.READY
        self.lock = asyncio.Lock()
        self.player = None

    def snapshot(self) -> SessionSnapshot:
        idle = self.state in (SessionState.DISCONNECTED, SessionState.READY, SessionState.FIXED)
        paused = self.state in (SessionState.PAUSED, SessionState.INTERRUPTED)
        has_route = self.cursor is not None
        capabilities = Capabilities(
            canConnect=self.last_point is None and self.state in (SessionState.DISCONNECTED, SessionState.READY),
            canStart=self.connection.is_open and idle and not has_route,
            canLocate=self.connection.is_open and idle and not has_route,
            canPause=self.state == SessionState.RUNNING,
            canResume=paused and self.last_point is not None,
            canRestart=has_route and self.state in (SessionState.PAUSED, SessionState.COMPLETED),
            canClear=self.udid is not None and self.state not in (SessionState.CONNECTING, SessionState.RECONNECTING),
            canChooseTrack=idle and not has_route,
            canEditPace=self.state not in (SessionState.CONNECTING, SessionState.RUNNING, SessionState.RECONNECTING),
            needsWakeLock=self.last_point is not None and self.state not in (SessionState.DISCONNECTED, SessionState.INTERRUPTED),
        )
        return SessionSnapshot(
            state=self.state, capabilities=capabilities,
            meters=self.cursor.meters if has_route else 0.0,
            total=self.cursor.route.total if has_route else 0.0,
            pace=self.cursor.pace if has_route else None,
            position=self.last_point, reconnects=self.reconnects, hasRoute=has_route,
        )

    def event(self, message=None):
        payload = dict(event='status', **self.snapshot().to_wire())
        if message:
            payload['message'] = message
        self.emit(payload)

    async def devices(self):
        return {'devices': await asyncio.wait_for(self.connection.devices(), 20)}

    async def connect(self, udid, prepare=False):
        if not self.snapshot().capabilities.canConnect:
            raise RuntimeError('请先恢复真实定位，或使用继续恢复当前会话。')
        self.udid = udid
        self.state = SessionState.CONNECTING
        self.event('正在连接手机。')
        async with self.lock:
            try:
                await asyncio.wait_for(self.connection.open(udid, prepare, self.event), 700 if prepare else 40)
            except Exception:
                self.state = SessionState.DISCONNECTED
                self.event('连接失败，请检查数据线、解锁状态及开发者镜像。')
                raise
            self.state = SessionState.READY
            self.event('手机已连接。')
        return self.snapshot().to_wire()

    async def stop_updates(self):
        player = self.player
        if player is None or player is asyncio.current_task():
            return
        async with self.lock:
            self.player = None
            player.cancel()
        try:
            await player
        except asyncio.CancelledError:
            pass

    def start_updates(self):
        self.player = asyncio.create_task(self.play())

    async def place(self, point):
        try:
            await self.connection.set(point)
        except Exception:
            if self.state not in (SessionState.RECONNECTING, SessionState.INTERRUPTED):
                self.suspended_state = self.state
            self.state = SessionState.INTERRUPTED if self.last_point is not None else SessionState.DISCONNECTED
            self.event('定位更新未成功，位置与进度已保留。')
            raise

    async def locate(self, point):
        if not self.snapshot().capabilities.canLocate:
            raise RuntimeError('请先结束当前轨迹，再设置固定位置。')
        point = Coordinate.parse(point)
        await self.stop_updates()
        async with self.lock:
            await self.place(point)
            self.last_point = point
            self.state = SessionState.FIXED
            self.event('已固定位置。')
        self.start_updates()
        return self.snapshot().to_wire()

    async def start(self, points, base, amplitude):
        if not self.snapshot().capabilities.canStart:
            raise RuntimeError('请先连接设备；已有轨迹请使用继续或重新开始。')
        route, profile = Route(points), Profile(base, amplitude)
        await self.stop_updates()
        async with self.lock:
            await self.place(route.points[0])
            self.cursor = Cursor(route, profile)
            self.last_point = route.points[0]
            self.reconnects = 0
            self.state = SessionState.RUNNING
            self.event('轨迹播放中。')
        self.start_updates()
        return self.snapshot().to_wire()

    async def pause(self):
        if not self.snapshot().capabilities.canPause:
            raise RuntimeError('当前没有正在播放的轨迹。')
        await self.stop_updates()
        async with self.lock:
            self.state = SessionState.PAUSED
            self.event('已暂停，可调整配速后继续。')
        self.start_updates()
        return self.snapshot().to_wire()

    async def resume(self, base=None, amplitude=None):
        if not self.snapshot().capabilities.canResume:
            raise RuntimeError('当前没有可继续的会话。')
        profile = Profile(base, amplitude) if self.cursor is not None else None
        await self.stop_updates()
        async with self.lock:
            try:
                if not self.connection.is_open:
                    await asyncio.wait_for(self.connection.open(self.udid), 40)
                await self.place(self.last_point)
            except Exception:
                self.suspended_state = SessionState.PAUSED if self.cursor else SessionState.FIXED
                self.state = SessionState.INTERRUPTED
                self.event('连接尚未恢复，位置和进度已保留。')
                raise
            if self.cursor is not None:
                self.cursor.configure(profile)
                self.state = SessionState.COMPLETED if self.cursor.meters >= self.cursor.route.total else SessionState.RUNNING
            else:
                self.state = SessionState.FIXED
            self.event('已从暂停位置继续。' if self.cursor else '已恢复固定位置。')
        self.start_updates()
        return self.snapshot().to_wire()

    async def restart(self, base, amplitude):
        if not self.snapshot().capabilities.canRestart:
            raise RuntimeError('请先暂停轨迹，再重新开始。')
        profile = Profile(base, amplitude)
        await self.stop_updates()
        async with self.lock:
            route = self.cursor.route
            await self.place(route.points[0])
            self.cursor = Cursor(route, profile)
            self.last_point = route.points[0]
            self.state = SessionState.RUNNING
            self.event('轨迹播放中。')
        self.start_updates()
        return self.snapshot().to_wire()

    async def tick(self, delta):
        async with self.lock:
            if delta > 3:
                self.suspended_state = self.state
                self.state = SessionState.INTERRUPTED
                self.event('更新中断，位置与进度已保留。')
                return
            proposal = self.cursor.proposal(delta) if self.state == SessionState.RUNNING else None
            point = proposal[2] if proposal else self.last_point
            if point is None:
                return
            await self.place(point)
            if proposal:
                self.cursor.commit(proposal)
                self.last_point = point
                if self.cursor.meters >= self.cursor.route.total:
                    self.state = SessionState.COMPLETED
                    self.event('轨迹已完成。')
            self.event()

    async def recover(self):
        intent = self.suspended_state if self.state == SessionState.INTERRUPTED else self.state
        self.suspended_state = intent
        self.state = SessionState.RECONNECTING
        self.event('连接中断，正在重连同一台手机。')
        for delay in (1, 2, 4, 8, 8):
            await asyncio.sleep(delay)
            self.state = SessionState.RECONNECTING
            try:
                async with self.lock:
                    await asyncio.wait_for(self.connection.open(self.udid), 25)
                    await self.place(self.last_point)
                self.state = intent
                self.reconnects += 1
                self.event('已重连，位置与进度已保留。')
                return True
            except Exception:
                continue
        self.state = SessionState.INTERRUPTED
        self.event('重连未成功，请检查手机后点击继续。')
        return False

    async def play(self):
        previous = time.monotonic()
        try:
            while True:
                await asyncio.sleep(1)
                now = time.monotonic()
                delta, previous = now - previous, now
                try:
                    await self.tick(delta)
                except Exception:
                    if not await self.recover():
                        return
                    previous = time.monotonic()
                if self.state == SessionState.INTERRUPTED:
                    return
        except asyncio.CancelledError:
            raise

    async def clear(self):
        if self.udid is None:
            raise RuntimeError('请先连接手机。')
        await self.stop_updates()
        async with self.lock:
            try:
                if not self.connection.is_open:
                    await asyncio.wait_for(self.connection.open(self.udid), 40)
                await self.connection.clear()
            except Exception:
                self.suspended_state = self.state
                self.state = SessionState.INTERRUPTED
                self.event('恢复定位未确认，请检查连接后重试。')
                raise
            self.last_point = None
            self.cursor = None
            self.state = SessionState.READY
            self.event('已发送恢复真实定位命令。')
        return self.snapshot().to_wire()

    async def shutdown(self):
        await self.stop_updates()
        restored = self.last_point is None
        try:
            if self.last_point is not None:
                await self.clear()
                restored = True
        except Exception:
            self.emit(dict(event='warning', message='未能确认恢复定位，请重连后手动恢复。'))
        finally:
            await self.connection.close()
        return restored
