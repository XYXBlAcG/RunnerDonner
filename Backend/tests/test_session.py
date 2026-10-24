import asyncio
from pathlib import Path
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from engine import Cursor, Profile, Route
from session import Session
from connection import DeviceConnection


class ServiceContext:
    def __init__(self, service):
        self.service = service

    async def __aenter__(self):
        return self.service

    async def __aexit__(self, *error):
        return False


class LocationService:
    def __init__(self, transport):
        self.transport = transport

    async def set(self, latitude, longitude):
        if self.transport.write_gate is not None:
            self.transport.write_started.set()
            await self.transport.write_gate.wait()
        if self.transport.failure:
            raise OSError('transport closed')
        self.transport.positions.append((latitude, longitude))

    async def clear(self):
        self.transport.clears += 1


class DeviceTransport(DeviceConnection):
    def __init__(self):
        super().__init__()
        self.positions = []
        self.opens = 0
        self.clears = 0
        self.failure = False
        self.write_gate = None
        self.write_started = asyncio.Event()

    async def open(self, udid, prepare=False, notify=None):
        self.opens += 1
        device = SimpleNamespace(serial=udid, is_usb=True)
        with patch('pymobiledevice3.usbmux.list_devices', new=AsyncMock(return_value=[device])), \
             patch('pymobiledevice3.remote.userspace_tunnel.UserspaceRsdTunnel', return_value=ServiceContext(object())), \
             patch('pymobiledevice3.services.dvt.instruments.dvt_provider.DvtProvider', return_value=ServiceContext(object())), \
             patch('pymobiledevice3.services.dvt.instruments.location_simulation.LocationSimulation', return_value=ServiceContext(LocationService(self))):
            await super().open(udid, prepare, notify)


class SessionChecks(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.transport = DeviceTransport()
        self.events = []
        self.session = Session(connection=self.transport, emit=self.events.append)
        await self.session.connect('test-phone')
        self.points = [[32, 118], [32.001, 118], [32.001, 118.001]]

    async def asyncTearDown(self):
        await self.session.shutdown()

    async def test_fixed_location_requires_no_route_and_never_advances(self):
        await self.session.locate([32.0004, 118.0003])
        await self.session.tick(1)
        await self.session.tick(1)
        self.assertIsNone(self.session.cursor)
        self.assertEqual(self.transport.positions[-3:], [(32.0004, 118.0003)] * 3)
        self.assertEqual(self.events[-1]['state'], 'fixed')
        self.assertEqual(self.events[-1]['meters'], 0)
        self.assertFalse(self.events[-1]['capabilities']['canResume'])

    async def test_pause_keeps_progress_and_position(self):
        await self.session.start(self.points, 360, 0)
        await self.session.tick(1)
        before = self.session.cursor.meters, self.session.cursor.elapsed, self.transport.positions[-1]
        await self.session.pause()
        await self.session.tick(2)
        after = self.session.cursor.meters, self.session.cursor.elapsed, self.transport.positions[-1]
        self.assertEqual(before, after)
        self.assertTrue(self.events[-1]['capabilities']['canResume'])
        self.assertFalse(self.events[-1]['capabilities']['canStart'])

    async def test_resume_uses_paused_position_and_existing_connection(self):
        await self.session.start(self.points, 360, 0)
        await self.session.tick(2)
        await self.session.pause()
        previous = self.transport.positions[-1]
        distance = self.session.cursor.meters
        opens = self.transport.opens
        await self.session.resume(360, 0)
        self.assertEqual(self.transport.positions[-1], previous)
        self.assertNotEqual(previous, tuple(self.points[0]))
        self.assertEqual(self.transport.opens, opens)
        await self.session.tick(1)
        self.assertGreater(self.session.cursor.meters, distance)

    async def test_resume_applies_new_pace_without_resetting_distance_or_elapsed(self):
        await self.session.start(self.points, 360, 0)
        await self.session.tick(2)
        await self.session.pause()
        distance, elapsed = self.session.cursor.meters, self.session.cursor.elapsed
        await self.session.resume(300, 0)
        self.assertEqual(self.session.cursor.meters, distance)
        self.assertEqual(self.session.cursor.elapsed, elapsed)
        await self.session.tick(1)
        self.assertAlmostEqual(self.session.cursor.meters - distance, 1000 / 300)
        self.assertEqual(self.events[-1]['pace'], 300)

    async def test_resume_applies_new_variation_without_resetting_route(self):
        await self.session.start(self.points, 360, 0)
        await self.session.tick(2)
        await self.session.pause()
        cursor = self.session.cursor
        await self.session.resume(330, 20)
        self.assertIs(self.session.cursor, cursor)
        for _ in range(40):
            await self.session.tick(0.1)
            self.assertGreaterEqual(self.events[-1]['pace'], 310)
            self.assertLessEqual(self.events[-1]['pace'], 350)
        self.assertEqual(cursor.profile.amplitude, 20)

    async def test_invalid_resume_preserves_paused_session(self):
        await self.session.start(self.points, 360, 0)
        await self.session.tick(1)
        await self.session.pause()
        cursor = self.session.cursor
        distance = cursor.meters
        writes = len(self.transport.positions)
        with self.assertRaises(ValueError):
            await self.session.resume(0, 20)
        self.assertEqual(self.session.state, 'paused')
        self.assertIs(cursor, self.session.cursor)
        self.assertEqual(cursor.meters, distance)
        self.assertEqual(len(self.transport.positions), writes)

    async def test_start_and_locate_cannot_discard_a_paused_route(self):
        await self.session.start(self.points, 360, 0)
        await self.session.tick(1)
        await self.session.pause()
        cursor = self.session.cursor
        with self.assertRaises(RuntimeError):
            await self.session.start(self.points, 360, 0)
        with self.assertRaises(RuntimeError):
            await self.session.locate([32, 118])
        self.assertIs(self.session.cursor, cursor)

    async def test_explicit_restart_is_the_only_way_back_to_start(self):
        await self.session.start(self.points, 360, 0)
        await self.session.tick(2)
        await self.session.pause()
        await self.session.restart(300, 10)
        self.assertEqual(self.session.cursor.meters, 0)
        self.assertEqual(self.transport.positions[-1], tuple(self.points[0]))

    async def test_failed_write_never_advances_cursor(self):
        await self.session.start(self.points, 360, 0)
        before = self.session.cursor.meters
        self.transport.failure = True
        with self.assertRaises(OSError):
            await self.session.tick(1)
        self.assertEqual(self.session.cursor.meters, before)

    async def test_clear_discards_route_and_resets_snapshot(self):
        await self.session.start(self.points, 360, 0)
        await self.session.tick(1)
        await self.session.pause()
        await self.session.clear()
        self.assertIsNone(self.session.cursor)
        self.assertEqual(self.events[-1]['meters'], 0)
        self.assertEqual(self.events[-1]['total'], 0)
        self.assertIsNone(self.events[-1]['position'])
        self.assertTrue(self.events[-1]['capabilities']['canLocate'])

    async def test_invalid_fixed_coordinate_preserves_session(self):
        await self.session.locate([32, 118])
        writes = len(self.transport.positions)
        with self.assertRaises(ValueError):
            await self.session.locate([float('nan'), 118])
        self.assertEqual(len(self.transport.positions), writes)
        self.assertEqual(self.session.last_point, (32, 118))

    async def test_long_scheduling_gap_pauses_without_catchup(self):
        await self.session.start(self.points, 360, 0)
        await self.session.tick(1)
        previous = self.session.cursor.meters
        await self.session.tick(20)
        self.assertEqual(self.session.cursor.meters, previous)
        self.assertEqual(self.session.state, 'interrupted')
        self.assertTrue(self.events[-1]['capabilities']['canResume'])

    async def test_failed_location_change_marks_the_retained_position_interrupted(self):
        await self.session.locate([32, 118])
        self.transport.failure = True
        with self.assertRaises(OSError):
            await self.session.locate([32.001, 118])
        self.assertEqual(self.session.state, 'interrupted')
        self.assertEqual(self.session.last_point, (32, 118))
        self.assertTrue(self.events[-1]['capabilities']['canResume'])

    async def test_same_pace_resume_preserves_the_existing_waveform(self):
        await self.session.start(self.points, 360, 15)
        await self.session.tick(2)
        profile = self.session.cursor.profile
        pace = self.session.cursor.pace
        await self.session.pause()
        await self.session.resume(360, 15)
        self.assertIs(self.session.cursor.profile, profile)
        self.assertEqual(self.session.cursor.pace, pace)

    async def test_reconnect_of_a_paused_route_does_not_start_running(self):
        await self.session.start(self.points, 360, 0)
        await self.session.tick(1)
        await self.session.pause()
        await self.session.stop_updates()
        before = self.session.cursor.meters
        self.assertTrue(await self.session.recover())
        self.assertEqual(self.session.state, 'paused')
        await self.session.tick(1)
        self.assertEqual(self.session.cursor.meters, before)

    async def test_pause_waits_for_in_flight_write_before_freezing_cursor(self):
        await self.session.start(self.points, 360, 0)
        gate = asyncio.Event()
        self.transport.write_gate = gate
        pause = None
        try:
            await asyncio.wait_for(self.transport.write_started.wait(), 2)
            pause = asyncio.create_task(self.session.pause())
            await asyncio.sleep(0.02)
            self.assertFalse(pause.done())
            gate.set()
            await pause
            self.assertGreater(self.session.cursor.meters, 0)
            self.assertEqual(self.session.state, 'paused')
            self.assertEqual(self.transport.positions[-1], tuple(self.session.last_point))
        finally:
            gate.set()
            if pause is not None:
                await pause

    async def test_fixed_position_recovery_does_not_require_pace(self):
        await self.session.locate([32, 118])
        await self.session.tick(20)
        await self.session.resume()
        self.assertEqual(self.session.state, 'fixed')
        self.assertIsNone(self.session.cursor)
        self.assertEqual(self.transport.positions[-1], (32, 118))


if __name__ == '__main__':
    unittest.main()
