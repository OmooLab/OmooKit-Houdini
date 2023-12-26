import hou
import os
import shutil
from pathlib import Path
import pyperclip


def copy_path(
    dir_parm: str,
    name_parm: str,
    version_parm: str=None,
    silence=False,
    node=None
):
    node = node or hou.pwd()
    dir = node.evalParm(dir_parm)
    name = node.evalParm(name_parm)
    name = f'{name}_{node.evalParm(version_parm)}' if version_parm else name
    
    copy_clip(str(Path(dir, name)), silence)


def copy_clip(content: str, silence=False):
    try:
        pyperclip.copy(content)
        if not silence:
            hou.ui.displayMessage(f'"{content}" is copyed to clipboard')
    except:
        if not silence:
            hou.ui.displayMessage('copy to clipboard failed')
        pass


def open_directory(
        dir_parm: str,
        name_parm: str,
        version_parm: str=None,
        node=None
):
    node = node or hou.pwd()
    dirname = node.evalParm(dir_parm)
    name = node.evalParm(name_parm)
    name = f'{name}_{node.evalParm(version_parm)}' if version_parm else name

    dir_path = Path(dirname, name).resolve()
    
    if dir_path.is_dir():
        path_str = dir_path.as_posix() + "/"
        hou.ui.showInFileBrowser(path_str)
    else:
        hou.ui.displayMessage(
            text="Could not open directory:\n{dir}.".format(
                dir=dir_path.as_posix()),
            severity=hou.severityType.ImportantMessage
        )


def auto_increase_verison(current: str, versions: list[str]):
    if current == "" \
            or (current.removeprefix("v")[:3].isnumeric() and len(current) == 4):
        max_index = 0

        for version in versions:
            index = version.removeprefix("v")[:3]
            if index.isnumeric():
                index = int(index)
                if index > max_index:
                    max_index = index

        max_index += 1
        return f"v{max_index:03d}"
    return current


def get_versions(
    dir: str,
    name: str,
    ext: str = None
):
    dir_path = Path(dir).resolve()
    if not dir_path.is_dir():
        return []

    versions = []

    for child in dir_path.iterdir():
        if ext:
            if child.is_file() and child.name.startswith(name+"_") and child.suffix == ext:
                versions.append(child.stem.removeprefix(name+"_"))

        else:
            if child.is_dir() and child.name.startswith(name+"_"):
                versions.append(child.stem.removeprefix(name+"_"))

    return versions


def generate_version_menu(
    dir_parm: str,
    name_parm: str,
    ext: str = None,
    node=None
):
    node = node or hou.pwd()
    versions = get_versions(
        node.evalParm(dir_parm),
        node.evalParm(name_parm),
        ext
    )

    menu = []
    for version in versions:
        menu.append(version)
        menu.append(version)

    return menu


def get_size(path: str):
    """Returns the `directory` size in bytes."""

    path: Path = Path(path).resolve()

    try:
        if path.is_file():
            return path.stat().st_size

        elif path.is_dir():
            total = 0
            for child in path.iterdir():
                if child.is_file():
                    # if it's a file, use stat() function
                    total += child.stat().st_size
                elif child.is_dir():
                    # if it's a directory, recursively call this function
                    total += get_size(child)

            return total
        else:
            return 0

    except Exception:
        return 0


def format_size(b, factor=1024, suffix="B"):
    """
    Scale bytes to its proper byte format
    e.g:
        1253656 => '1.20MB'
        1253656678 => '1.17GB'
    """
    for unit in ["", "K", "M", "G", "T", "P", "E", "Z"]:
        if b < factor:
            return "{0:.2f}{1}{2}".format(b, unit, suffix)
        b /= factor
    return "{0:.2f}Y{1}".format(b, suffix)


def delete_versions(
    dir_parm: str,
    name_parm: str,
    ext: str = None,
    node=None
):
    node = node or hou.pwd()
    dir = node.evalParm(dir_parm)
    name = node.evalParm(name_parm)

    versions = get_versions(dir, name, ext)

    entries = []
    for version in versions:
        version_name = f"{name}_{version}.{ext}" if ext else f"{name}_{version}"
        version_path = Path(dir, version_name)
        entries.append(
            f'{version} ({format_size(get_size(version_path))})'
        )

    entries.sort()
    selected_versions = hou.ui.selectFromList(
        entries,
        title="Delete Versions",
        column_header="Versions",
        width=300,
        height=300
    )

    remove_versions = []
    if selected_versions:
        for selected in selected_versions:
            version = entries[selected].split(' ')[0]
            remove_versions.append(version)

        remove_versions.sort()
        confirm_message = "Are you sure you want to delete the following versions:\n"
        confirm_message += "\n".join(remove_versions)

        confirm = hou.ui.displayMessage(
            confirm_message,
            buttons=("Yes", "No"),
            severity=hou.severityType.Warning,
            default_choice=(1),
            title="Remove Backup"
        )

        if confirm == 0:
            for version in remove_versions:
                version_name = f"{name}_{version}.{ext}" if ext else f"{name}_{version}"
                version_path = Path(dir, version_name)
                if version_path.is_file():
                    version_path.unlink(missing_ok=True)
                elif version_path.is_dir():
                    shutil.rmtree(version_path)
