#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int *array;
    size_t size;
} DynamicArray;

DynamicArray* initializeDynamicArray() {
    DynamicArray *dynArray = (DynamicArray*)malloc(sizeof(DynamicArray));
    if (dynArray == NULL) {
        fprintf(stderr, "Memory allocation failed\n");
        exit(EXIT_FAILURE);
    }
    dynArray->array = NULL;
    dynArray->size = 0;
    return dynArray;
}

void appendToDynamicArray(DynamicArray *dynArray, int value) {
    dynArray->size++;
    dynArray->array = (int*)realloc(dynArray->array, dynArray->size * sizeof(int));
    if (dynArray->array == NULL) {
        fprintf(stderr, "Memory reallocation failed\n");
        exit(EXIT_FAILURE);
    }
    dynArray->array[dynArray->size - 1] = value;
}

void freeDynamicArray(DynamicArray *dynArray) {
    free(dynArray->array);
    free(dynArray);
}

int main() {
    DynamicArray *arr = initializeDynamicArray();
    appendToDynamicArray(arr, 10);
    appendToDynamicArray(arr, 20);
    appendToDynamicArray(arr, 30);

    printf("Array: ");
    for (size_t i = 0; i < arr->size; i++) {
        printf("%d ", arr->array[i]);
    }
    printf("\n");

    freeDynamicArray(arr);

    return 0;
}
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int *array;
    size_t size;
} DynamicArray;

DynamicArray* initializeDynamicArray() {
    DynamicArray *dynArray = (DynamicArray*)malloc(sizeof(DynamicArray));
    if (dynArray == NULL) {
        fprintf(stderr, "Memory allocation failed\n");
        exit(EXIT_FAILURE);
    }
    dynArray->array = NULL;
    dynArray->size = 0;
    return dynArray;
}

void appendToDynamicArray(DynamicArray *dynArray, int value) {
    dynArray->size++;
    dynArray->array = (int*)realloc(dynArray->array, dynArray->size * sizeof(int));
    if (dynArray->array == NULL) {
        fprintf(stderr, "Memory reallocation failed\n");
        exit(EXIT_FAILURE);
    }
    dynArray->array[dynArray->size - 1] = value;
}

void freeDynamicArray(DynamicArray *dynArray) {
    free(dynArray->array);
    free(dynArray);
}

int main() {
    DynamicArray *arr = initializeDynamicArray();
    appendToDynamicArray(arr, 10);
    appendToDynamicArray(arr, 20);
    appendToDynamicArray(arr, 30);

    printf("Array: ");
    for (size_t i = 0; i < arr->size; i++) {
        printf("%d ", arr->array[i]);
    }
    printf("\n");

    freeDynamicArray(arr);

    return 0;
}
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int *array;
    size_t size;
} DynamicArray;

DynamicArray* initializeDynamicArray() {
    DynamicArray *dynArray = (DynamicArray*)malloc(sizeof(DynamicArray));
    if (dynArray == NULL) {
        fprintf(stderr, "Memory allocation failed\n");
        exit(EXIT_FAILURE);
    }
    dynArray->array = NULL;
    dynArray->size = 0;
    return dynArray;
}

void appendToDynamicArray(DynamicArray *dynArray, int value) {
    dynArray->size++;
    dynArray->array = (int*)realloc(dynArray->array, dynArray->size * sizeof(int));
    if (dynArray->array == NULL) {
        fprintf(stderr, "Memory reallocation failed\n");
        exit(EXIT_FAILURE);
    }
    dynArray->array[dynArray->size - 1] = value; // Corrected index
}

void freeDynamicArray(DynamicArray *dynArray) {
    free(dynArray->array);
    free(dynArray);
}

int main() {
    DynamicArray *arr = initializeDynamicArray();
    appendToDynamicArray(arr, 10);
    appendToDynamicArray(arr, 20);
    appendToDynamicArray(arr, 30);

    printf("Array: ");
    for (size_t i = 0; i < arr->size; i++) {
        printf("%d ", arr->array[i]);
    }
    printf("\n");

    freeDynamicArray(arr);

    return 0;
}
