# Working with Custom / Complex Imports
Working with Python imports when creating custom classes with complex inheritances across multiple directories and subdirectories requires a structured approach. Here are some guidelines to help you manage this process effectively:

## Organize Your Directory Structure
Ensure that your project has a clear directory structure. Group related modules in the same directory or subdirectory. This organization will make it easier to understand and maintain your code.
```
myproject/
├── __init__.py
├── main.py
├── package1/
│   ├── __init__.py
│   ├── module1.py
│   └── module2.py
└── package2/
    ├── __init__.py
    └── module3.py
```

## Use __init__.py Files 
Each directory or subdirectory containing Python modules should have an __init__.py file. This file can be empty, but its presence tells Python that the directory is a package from which modules can be imported. This is especially important for nested directories.

### Make a Directory a Python Package

At its simplest, __init__.py can be an empty file that signifies to Python that the directory it's in should be treated as a Python package. This allows the package's modules to be imported from other parts of the project.

### Initialize Package State

__init__.py can be used to perform any initialization needed for the package, such as setting up logging, checking for necessary resources, or other startup tasks.

### Import Management

It can be used to control what is exported when import * is used with the package. This is done by defining a list named __all__ which contains the names of modules or objects the package will export as part of its public API.

```
    __all__ = ['module1', 'module2']
```

### Simplify Imports

You can use it to simplify the import statements for users of your package. Instead of having to import deep module hierarchies, you can import them in __init__.py, allowing users to import them directly from the package.

```
    from .module1 import MyClass1
    from .module2 import function2
```

### Declare Dependencies (for older Python versions):

In some older Python projects, __init__.py might include dependency checks or similar import-time checks. This is less common now with the advent of package management tools like pip and environments like virtualenv.

### Package Documentation

Sometimes, __init__.py contains a docstring at the top of the file that explains what the package includes or its purpose. This can be helpful for developers who are new to the package.

### Subpackage Imports

For a package with subpackages, __init__.py can be used to import these subpackages to make them easier to access.
```
from . import subpackage1, subpackage2
```

## Absolute Imports
Prefer absolute imports over relative imports for clarity and to avoid confusion. An absolute import specifies the full path from the project’s root folder to the module being imported. For example, from myproject.mypackage.mymodule import MyClass.

In main.py:

```
from myproject.package1.module1 import MyClass1
```

## Relative Imports
Use relative imports carefully. They can be used when referring to modules in the same package or subpackage. For example, if module2.py is in the same directory as module1.py, you can use from .module1 import MyClass.
```
from .module1 import MyClass1
```

## Manage sys.path 
If you need to import modules from directories not automatically included in Python's search path, you can append these directories to sys.path. However, this approach should be used judiciously as it can lead to conflicts and maintenance issues.
```
import sys
sys.path.append('/path/to/myproject')
from myproject.package1.module1 import MyClass1
```

## Consistent Inheritance
For complex inheritance structures, ensure that your classes are consistently and correctly importing their parent classes. Mismanaged imports can lead to inheritance issues like missing methods or attributes.

module1.py
```
class BaseClass:
    pass

class MyClass1(BaseClass):
    pass
```

module2.py
```
from myproject.package1.module1 import MyClass1

class MyClass3(MyClass1):
    pass
```

## Circular Dependencies
Be cautious of circular dependencies, where two or more modules depend on each other. This can cause issues with imports. Restructure your code or use import statements inside functions or methods to avoid this.
