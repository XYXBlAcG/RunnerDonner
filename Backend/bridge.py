import asyncio
import json
import logging
import signal
import sys
from session import Session
from models import DeviceCommand


def emit(value):
    print(json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False), flush=True)


async def dispatch(session, request):
    match DeviceCommand(request.get('command')):
        case 'devices':
            return await session.devices()
        case 'connect':
            return await session.connect(request['device'], request.get('prepare', False))
        case 'locate':
            return await session.locate(request['point'])
        case 'start':
            return await session.start(request['points'], request['pace'], request['amplitude'])
        case 'pause':
            return await session.pause()
        case 'resume':
            return await session.resume(request.get('pace'), request.get('amplitude'))
        case 'restart':
            return await session.restart(request['pace'], request['amplitude'])
        case 'clear':
            return await session.clear()
        case 'status':
            return session.snapshot().to_wire()
        case 'shutdown':
            return {'restored': await session.shutdown()}
        case _:
            raise ValueError('未知命令')


async def main():
    logging.basicConfig(stream=sys.stderr, level=logging.WARNING)
    session = Session(emit=emit)
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader(limit=4 * 1024 * 1024)
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)
    stopping = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stopping.set)
    emit(dict(event='ready', protocol=2))
    session.event()
    try:
        while not stopping.is_set():
            read_task = asyncio.create_task(reader.readline())
            stop_task = asyncio.create_task(stopping.wait())
            done, pending = await asyncio.wait((read_task, stop_task), return_when=asyncio.FIRST_COMPLETED)
            for task in pending:
                task.cancel()
            await asyncio.gather(*pending, return_exceptions=True)
            if stop_task in done:
                break
            line = read_task.result()
            if not line:
                break
            request = {}
            try:
                request = json.loads(line)
                if not isinstance(request, dict):
                    raise ValueError('请求必须是对象')
                result = await dispatch(session, request)
                emit(dict(id=request.get('id'), ok=True, result=result))
                if request['command'] == 'shutdown':
                    break
            except Exception as error:
                emit(dict(id=request.get('id') if isinstance(request, dict) else None, ok=False, error=f'{type(error).__name__}: {error}'))
    finally:
        await session.shutdown()


if __name__ == '__main__':
    asyncio.run(main())
