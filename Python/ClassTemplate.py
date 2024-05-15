class MyClass:
    def __init__(self, parameter1, parameter2=None):  
        self.attribute1 = parameter1
        self.attribute2 = parameter2

    def my_method(self, arg1, arg2): 
        result = self.attribute1 + arg1 * arg2
        return result

    @staticmethod
    def utility_function(x, y):
      return x ** y

my_object = MyClass(5, 10)
result1 = my_object.my_method(3, 2)
result2 = MyClass.utility_function(4, 3)
print(my_object, result1, result2)
