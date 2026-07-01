
"""
SYNOPSIS

DESCRIPTION
    MetadataDTOAttribute class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Sept-03 - jgarcia - initial

LICENSE
    (C) onsemi 2024 All rights reserved.
"""
class MetadataDTOAttribute:
    def __init__(self, name, source=None, value=None):
        self.value = value
        self.source = source
        self.name = name

    @property
    def xml_value(self):
        return self.value

    @xml_value.setter
    def xml_value(self, value):
        self.value = value

    @property
    def xml_source(self):
        return self.source

    @xml_source.setter
    def xml_source(self, source):
        self.source = source

    @property
    def xml_name(self):
        return self.name

    @xml_name.setter
    def xml_name(self, name):
        self.name = name

    def __str__(self):
        return f"MetadataDTOAttribute(value='{self.value}', source={self.source}, name='{self.name}')"

    def clone(self):
        return MetadataDTOAttribute(self.name, self.source, self.value)