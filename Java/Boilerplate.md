# Boilerplate Java Code

### Improving PrintLn
```
    private void print(String userInput) {
        System.out.println(userInput);
    }
```

### Capture user input
Requires: `import javax.swing.JOptionPane;`
```
    private String input(String userInput){
        String userEntered = "";
        while (userEntered.equals("")) {
            try {
                userEntered = JOptionPane.showInputDialog(userInput);
            } catch (Exception e) {
                print("Error: " + "\n" + e + "\n" + "Please re-enter the value:");
            }   
        }
        return userEntered;
    }
```

### Basic class
```
public class MyClass {
    // Instance variables
    private int number;
    private String name;

    // Constructor
    public MyClass(int number, String name) {
        this.number = number;
        this.name = name;
    }

    // Getters and setters
    public int getNumber() {
        return number;
    }

    public void setNumber(int number) {
        this.number = number;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    // Method
    public void displayInfo() {
        System.out.println("Number: " + number + ", Name: " + name);
    }

    // Main method
    public static void main(String[] args) {
        MyClass myClass = new MyClass(1, "Sample");
        myClass.displayInfo();
    }
}

```

### Read file
```
import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;

public class ReadFileExample {
    public static void main(String[] args) {
        String filePath = "C:/Temp/file.txt";
        
        try (BufferedReader br = new BufferedReader(new FileReader(filePath))) {
            String line;
            while ((line = br.readLine()) != null) {
                System.out.println(line);
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
```

### Write file
```
import java.io.BufferedWriter;
import java.io.FileWriter;
import java.io.IOException;

public class WriteFileExample {
    public static void main(String[] args) {
        String filePath = "/home/user/output.txt";
        String content = "HelloWorld";
        
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(filePath))) {
            bw.write(content);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
```


### HTTP Request
```
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;

public class HttpGetRequestExample {
    public static void main(String[] args) {
        try {
            URL url = new URL("http://example.com");
            HttpURLConnection con = (HttpURLConnection) url.openConnection();
            con.setRequestMethod("GET");

            int status = con.getResponseCode();
            BufferedReader in = new BufferedReader(new InputStreamReader(con.getInputStream()));
            String inputLine;
            StringBuilder content = new StringBuilder();
            while ((inputLine = in.readLine()) != null) {
                content.append(inputLine);
            }
            in.close();
            con.disconnect();

            System.out.println(content.toString());
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
```

### Threading
```
public class SimpleThread {
    public static void main(String[] args) {
        Thread thread = new Thread(() -> {
            for (int i = 0; i < 5; i++) {
                System.out.println("In the thread: " + i);
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }
            }
        });

        thread.start();
        System.out.println("In the main thread.");
    }
}
```
