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
