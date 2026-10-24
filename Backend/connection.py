import asyncio
from contextlib import AsyncExitStack
from collections.abc import Awaitable
from models import Coordinate


class DeviceConnection:
    def __init__(self):
        self.stack = None
        self.location = None

    @property
    def is_open(self) -> bool:
        return self.location is not None

    async def devices(self) -> list[dict]:
        from pymobiledevice3.usbmux import list_devices
        from pymobiledevice3.lockdown import create_using_usbmux
        devices = []
        for device in await list_devices():
            if not device.is_usb:
                continue
            try:
                async with await create_using_usbmux(serial=device.serial, autopair=False, connection_type='USB') as client:
                    devices.append(dict(id=device.serial, name=client.all_values.get('DeviceName', 'iPhone'), version=client.product_version))
            except Exception as error:
                devices.append(dict(id=device.serial, name='USB 设备（请解锁并信任）', version='', error=type(error).__name__))
        return devices

    async def close(self):
        stack, self.stack = self.stack, None
        self.location = None
        if stack:
            await asyncio.wait_for(stack.aclose(), 10)

    async def open(self, udid: str, prepare=False, notify=None):
        from pymobiledevice3.remote.userspace_tunnel import UserspaceRsdTunnel
        from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
        from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation
        from pymobiledevice3.usbmux import list_devices
        if not udid or not any(device.serial == udid and device.is_usb for device in await list_devices()):
            raise RuntimeError('指定 USB 手机未连接，请检查数据线并解锁。')
        await self.close()
        stack = AsyncExitStack()
        try:
            rsd = await stack.enter_async_context(UserspaceRsdTunnel(serial=udid, autopair=False, remotepairing_fallback=False))
            if prepare:
                from developer_image import prepare as prepare_image
                await prepare_image(rsd, notify or (lambda message: None))
                await stack.aclose()
                stack = AsyncExitStack()
                rsd = await stack.enter_async_context(UserspaceRsdTunnel(serial=udid, autopair=False, remotepairing_fallback=False))
            dvt = await stack.enter_async_context(DvtProvider(rsd))
            location = await stack.enter_async_context(LocationSimulation(dvt))
            self.stack, self.location = stack, location
        except BaseException:
            await stack.aclose()
            raise

    async def set(self, point: Coordinate):
        if not self.is_open:
            raise ConnectionError('定位通道未连接。')
        await self._complete(self.location.set(*point))

    async def clear(self):
        if not self.is_open:
            raise ConnectionError('定位通道未连接。')
        await self._complete(self.location.clear())

    async def _complete(self, operation: Awaitable[None]):
        try:
            await asyncio.wait_for(operation, 8)
        except Exception:
            await self.close()
            raise
