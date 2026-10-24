"""iOS 27 Cryptex preparation; GitHub access is exclusively through gh."""
import asyncio
import os
from pathlib import Path
import plistlib
import shutil

IMAGE_REVISION='6eae353ae694bda1c421d4a3eee5459ae59c99a1'
FILES=('Image.dmg','Image.dmg.trustcache','Image.dmg.cryptex_info','Image.dmg.root_hash','BuildManifest.plist')


def find_gh():
    candidates=[shutil.which('gh'),'/opt/homebrew/bin/gh','/usr/local/bin/gh']
    return next((p for p in candidates if p and os.access(p,os.X_OK)),None)


async def fetch_assets(notify):
    gh=find_gh()
    if not gh:raise RuntimeError('准备镜像需要 GitHub CLI（gh），请先安装或用 Xcode 准备设备。')
    cache=Path.home()/'Library/Caches/RunnerDonner/DeveloperImages'/IMAGE_REVISION
    cache.mkdir(parents=True,exist_ok=True)
    for name in FILES:
        target=cache/name
        if target.exists() and target.stat().st_size>0:continue
        notify(f'正在下载开发者镜像：{name}')
        partial=cache/(name+'.partial')
        endpoint=f'repos/doronz88/DeveloperDiskImage/contents/PersonalizedImages/Xcode_iOS_DDI_Cryptex/{name}?ref={IMAGE_REVISION}'
        with partial.open('wb') as output:
            process=await asyncio.create_subprocess_exec(gh,'api',endpoint,'-H','Accept: application/vnd.github.raw+json',stdout=output,stderr=asyncio.subprocess.PIPE)
            try:
                _,error=await asyncio.wait_for(process.communicate(),120)
            except BaseException:
                if process.returncode is None:process.kill();await process.wait()
                raise
        if process.returncode!=0:
            raise RuntimeError(f'镜像下载失败（{name}），请检查 gh 登录或网络。')
        if partial.stat().st_size==0:raise RuntimeError(f'镜像文件为空：{name}')
        partial.replace(target)
    # Refuse JSON error bodies or an unrelated manifest before device personalization.
    manifest=plistlib.loads((cache/'BuildManifest.plist').read_bytes())
    if not manifest.get('BuildIdentities'):raise RuntimeError('开发者镜像清单无效。')
    return cache


async def prepare(rsd,notify):
    from pymobiledevice3.services.cryptexd import CryptexdService
    from pymobiledevice3.services.mobile_image_mounter import PersonalizedImageMounter
    if int(rsd.product_version.split('.')[0])<27:
        raise RuntimeError('此镜像准备入口仅用于 iOS 27 及以上。')
    service=CryptexdService(rsd)
    if any(image.identifier=='com.apple.MobileAsset.DDI' for image in await service.copy_installed()):
        notify('Cryptex 开发者镜像已安装。');return
    async with PersonalizedImageMounter(lockdown=rsd) as mounter:
        if await mounter.is_image_mounted('Personalized'):
            notify('开发者镜像已就绪，保留现有镜像。');return
    directory=await fetch_assets(notify)
    notify('正在向 Apple 请求开发者镜像签名并安装 Cryptex，请保持手机解锁。')
    await service.auto_install_ddi(restore_dir=directory)
