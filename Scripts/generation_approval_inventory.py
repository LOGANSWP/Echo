"""4.0k: observed dependency and license inventory helpers; no approvals."""
from pathlib import PurePosixPath
from packaging.markers import default_environment
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name


def dependency_graph(roots, provider):
    """Resolve installed base/extra requirements; fail on missing/version drift.

    provider(name) returns version/requires. Platform markers use this host;
    omitted optional extras are not treated as runtime dependencies.
    """
    pending = [Requirement(r) for r in roots]
    graph = {}
    extras = {}
    environment = default_environment()
    while pending:
        requirement = pending.pop(0)
        name = canonicalize_name(requirement.name)
        try:
            package = provider(name)
        except Exception as error:
            raise ValueError('Missing dependency: ' + name) from error
        if requirement.url or package['version'] not in requirement.specifier:
            raise ValueError('Unsupported URL or incompatible dependency: ' + str(requirement))
        selected = extras.get(name, set()) | set(requirement.extras)
        if name in graph and selected == extras[name]:
            continue
        extras[name] = selected
        dependencies = set()
        for raw in package.get('requires') or []:
            child = Requirement(raw)
            active = not child.marker or any(child.marker.evaluate({**environment, 'extra': extra})
                                             for extra in selected | {''})
            if active:
                dependencies.add(canonicalize_name(child.name))
                pending.append(child)
        graph[name] = {'version': package['version'], 'dependencies': sorted(dependencies),
                       'selectedExtras': sorted(selected)}
    return dict(sorted(graph.items()))


def is_license_document(path):
    name = PurePosixPath(str(path)).name.lower()
    if name.endswith(('.py', '.pyc', '.so', '.dylib')):
        return False
    return name.split('.')[0] in {'license', 'licence', 'notice', 'copying', 'authors'}
