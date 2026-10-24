from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bridge import dispatch
from generate_protocol import render
from models import Capabilities, SessionSnapshot, SessionState
from session import Session
from test_session import DeviceTransport


class ProtocolChecks(unittest.IsolatedAsyncioTestCase):
    async def test_initial_native_capabilities_match_disconnected_session(self):
        session = Session()
        self.assertEqual(Capabilities(), session.snapshot().capabilities)

    async def test_generated_swift_matches_model_source(self):
        path = Path(__file__).resolve().parents[2] / 'LocationController/DeviceProtocol.swift'
        self.assertEqual(path.read_text(), render())

    async def test_route_commands_keep_the_same_cursor(self):
        events = []
        session = Session(connection=DeviceTransport(), emit=events.append)
        try:
            await dispatch(session, dict(command='connect', device='test-phone'))
            await dispatch(session, dict(command='start', points=[[32, 118], [32.001, 118]], pace=360, amplitude=0))
            await session.tick(1)
            cursor = session.cursor
            paused = await dispatch(session, dict(command='pause'))
            self.assertTrue(paused['capabilities']['canResume'])
            resumed = await dispatch(session, dict(command='resume', pace=300, amplitude=15))
            self.assertIs(session.cursor, cursor)
            self.assertEqual(resumed['meters'], paused['meters'])
            self.assertEqual(resumed['state'], 'running')
        finally:
            await session.shutdown()

    async def test_fixed_coordinate_command_uses_the_session_writer(self):
        session = Session(connection=DeviceTransport())
        try:
            await dispatch(session, dict(command='connect', device='test-phone'))
            result = await dispatch(session, dict(command='locate', point=[32.2, 118.3]))
            self.assertEqual(result['position'], dict(latitude=32.2, longitude=118.3))
            self.assertEqual(result['total'], 0)
            self.assertEqual(result['state'], 'fixed')
        finally:
            await session.shutdown()


if __name__ == '__main__':
    unittest.main()
