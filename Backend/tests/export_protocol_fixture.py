import asyncio
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from session import Session
from test_session import DeviceTransport


async def main():
    snapshots = []
    session = Session(connection=DeviceTransport(), emit=snapshots.append)
    try:
        await session.connect('test-phone')
        await session.locate([32, 118])
        await session.clear()
        await session.start([[32, 118], [32.001, 118]], 360, 0)
        await session.tick(1)
        await session.pause()
        await session.resume(300, 15)
        await session.tick(1)
        await session.clear()
    finally:
        await session.shutdown()
    Path(sys.argv[1]).write_text(json.dumps(snapshots, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    asyncio.run(main())
