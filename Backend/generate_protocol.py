from dataclasses import fields, is_dataclass
from pathlib import Path
from types import UnionType
from typing import get_args, get_origin, get_type_hints
from models import Capabilities, Coordinate, DeviceCommand, SessionSnapshot, SessionState


def swift_type(annotation):
    if get_origin(annotation) is UnionType:
        return swift_type(next(item for item in get_args(annotation) if item is not type(None))) + '?'
    return {bool: 'Bool', int: 'Int', float: 'Double', str: 'String'}.get(annotation, getattr(annotation, '__name__', str(annotation)))


def render():
    output = ['import Foundation', '']
    for enumeration in (DeviceCommand, SessionState):
        output.append(f'enum {enumeration.__name__}: String, Codable {{')
        output.extend(f'    case {item.value}' for item in enumeration)
        output.extend(['}', ''])
    for model in (Coordinate, Capabilities, SessionSnapshot):
        conformance = 'Codable, Equatable' if model is Coordinate else 'Codable'
        output.append(f'struct {model.__name__}: {conformance} {{')
        hints = get_type_hints(model)
        defaults = {field.name: field.default for field in fields(model)} if is_dataclass(model) else {}
        for name, annotation in hints.items():
            default = f' = {str(defaults[name]).lower()}' if isinstance(defaults.get(name), bool) else ''
            output.append(f'    var {name}: {swift_type(annotation)}{default}')
        output.extend(['}', ''])
    return '\n'.join(output)


if __name__ == '__main__':
    destination = Path(__file__).resolve().parents[1] / 'LocationController/DeviceProtocol.swift'
    destination.write_text(render())
