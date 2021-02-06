from typing import Any, Iterable, List, Mapping

from opta.module import Module


class LinkProcessor:
    def process(self, modules: Iterable[Module]) -> None:
        for m in modules:
            for k, v in m.data.items():
                if not isinstance(v, list):
                    continue

                new_items: List[Mapping[Any, Any]] = []
                to_remove = []
                for item in v:
                    if "_link" in item:
                        to_remove.append(item)
                        new_items.extend(self.find_items(modules, item["_link"]))

                for r in to_remove:
                    v.remove(r)

                for i in new_items:
                    v.append(i)

    def find_items(
        self, modules: Iterable[Module], target: str
    ) -> Iterable[Mapping[Any, Any]]:
        target_module: Any = None
        new_items: List[Mapping[Any, Any]] = []

        target_module = next((module for module in modules if module.key == target), {})

        for k, v in target_module.desc["outputs"].items():
            new_items.append(
                {
                    "name": f"{target_module.key}_{k}",
                    "value": f"${{{{module.{target_module.key}.{k}}}}}",
                }
            )

        return new_items
