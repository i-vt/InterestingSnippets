# Obfuscating code from wondering coder's eyes

## Why? 
If you don't want your "sauce" code to be yoinked & sploinked into a counterfit product - make it harder to decompile :)

## Discaimer:
- Readability and Maintenance: These techniques significantly reduce the readability and maintainability of your code. They should be used judiciously.
- Performance Impact: Some obfuscation techniques can negatively impact the performance of your application.
- Not Foolproof: These techniques do not guarantee that your code cannot be decompiled or understood; they merely increase the effort required to do so.
- Legal and Ethical Concerns: Ensure your methods comply with legal and ethical standards, particularly if using cryptography or deploying software in environments with strict regulations.


## Techniques:

### Use Macros
```
#define A 5
#define B(x, y) ((x) * (y))

int main() {
    int result = B(A, 3); // Equivalent to result = 5 * 3;
    return 0;
}
```

### Complex & irrelevant workflow
```
int complexFunction(int x) {
    switch (x % 4) {
    case 0: x = x * 2; break;
    case 1: x = x / 2; break;
    case 2: x = x + 2; break;
    case 3: x = x - 2; break;
    }
    return (x % 2 == 0) ? x : complexFunction(x + 1);
}
```

### Assembly? Because why not?

```
int add(int a, int b) {
    int result;
    __asm__(
        "addl %%ebx, %%eax;"
        : "=a" (result) 
        : "a" (a), "b" (b)
    );
    return result;
}
```

### Pointer and memory magician activities
```
int main() {
    int a = 5;
    int* ptr = &a;
    *ptr += 3; // a is now 8
    return 0;
}
```

### Template metaprogramming (((Because why not?)))
```
template<int N>
struct Factorial {
    enum { value = N * Factorial<N - 1>::value };
};

template<>
struct Factorial<0> {
    enum { value = 1 };
};

int main() {
    int x = Factorial<5>::value; // Compile-time calculation of factorial 5
    return 0;
}
```


### Goto like no other. Just because why not?
```
void function() {
    int x = 0;
    start:
    if (x < 5) {
        x++;
        goto start;
    }
    return;
}
```
