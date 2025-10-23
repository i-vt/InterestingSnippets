using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Text.Json;

// 1. Safely getting the value from the dictionary
public static class DictionaryExtensions
{
    public static TValue GetValueOrDefault<TKey, TValue>(this Dictionary<TKey, TValue> dict, TKey key, TValue defaultValue = default)
    {
        return dict is null ? throw new ArgumentNullException(nameof(dict)) : dict.TryGetValue(key, out var value) ? value : defaultValue;
    }
}

// 2. Simple timer to measure the execution time
public static class PerformanceTimer
{
    public static TimeSpan Measure(Action action)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        action();
        stopwatch.Stop();
        return stopwatch.Elapsed;
    }
}

// 3. Asynchronous Try-Catch with result return
public static class AsyncHelper
{
    public static async Task<(T Result, Exception Error)> TryAsync<T>(Func<Task<T>> func)
    {
        try
        {
            var result = await func();
            return (result, null);
        }
        catch (Exception ex)
        {
            return (default, ex);
        }
    }
}

// 4. Fast JSON serialization/deserialization
public static class JsonHelper
{
    public static string Serialize<T>(T obj, bool indented = false)
    {
        return JsonSerializer.Serialize(obj, new JsonSerializerOptions { WriteIndented = indented });
    }

    public static T Deserialize<T>(string json)
    {
        return JsonSerializer.Deserialize<T>(json);
    }
}

// 5. Checking for null with default value
public static class NullCheckExtensions
{
    public static T IfNull<T>(this T obj, T defaultValue) where T : class
    {
        return obj ?? defaultValue;
    }
}

// 6. A convenient way to create lazy initialization
public static class LazyInitializer
{
    public static T GetOrCreate<T>(ref T field, Func<T> factory) where T : class
    {
        if (field == null)
        {
            field = factory();
        }
        return field;
    }
}

// 7. Fast filtering and mapping of the collection
public static class CollectionExtensions
{
    public static IEnumerable<TOut> FilterAndMap<TIn, TOut>(
        this IEnumerable<TIn> source,
        Func<TIn, bool> predicate,
        Func<TIn, TOut> selector)
    {
        return source.Where(predicate).Select(selector);
    }
}

// 8. A simple logger to the console with a timestamp
public static class SimpleLogger
{
    public static void Log(string message, string level = "INFO")
    {
        Console.WriteLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {level}: {message}");
    }
}

public class Program
{
    public static async Task Main()
    {
        //1
        var dict = new Dictionary<string, int> { { "key1", 42 } };
        var value = dict.GetValueOrDefault("key2", 0);
        SimpleLogger.Log($"Dictionary value: {value}");

        //2
        var time = PerformanceTimer.Measure(() =>
        {
            for (int i = 0; i < 1000000; i++) { }
        });
        SimpleLogger.Log($"Loop took: {time.TotalMilliseconds}ms");

        //3
        var (result, error) = await AsyncHelper.TryAsync(async () =>
        {
            await Task.Delay(100);
            return "Success";
        });
        SimpleLogger.Log(error == null ? result : $"Error: {error.Message}");

        //4
        var obj = new { Name = "Test", Value = 123 };
        var json = JsonHelper.Serialize(obj, true);
        SimpleLogger.Log($"JSON: {json}");

        //5
        string str = null;
        var safeStr = str.IfNull("Default");
        SimpleLogger.Log($"Safe string: {safeStr}");

        //6
        List<string> lazyList = null;
        var list = LazyInitializer.GetOrCreate(ref lazyList, () => new List<string>());
        SimpleLogger.Log($"Lazy list count: {list.Count}");

        //7
        var numbers = new List<int> { 1, 2, 3, 4, 5 };
        var evenSquares = numbers.FilterAndMap(x => x % 2 == 0, x => x * x);
        SimpleLogger.Log($"Even squares: {string.Join(", ", evenSquares)}");
    }
}