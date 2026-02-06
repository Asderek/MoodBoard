# 3D MoodBoard

A spatial moodboard application built with Godot 4. Organizes images and notes in a 3D environment with physics-based interactions.

<img width="1717" height="959" alt="image" src="https://github.com/user-attachments/assets/d74e4bcd-08b4-42e4-ae82-ed07033c6773" />

Nodes can be freely moved, aligned to a grid, or arranged in a timeline direction.

<img width="1712" height="962" alt="image" src="https://github.com/user-attachments/assets/1368bda7-2045-4526-9dd4-ac76572e8b50" />

Nodes can be entered and other nodes can be created inside it. Images can be drag and dropped or clipboarded in.


## How to Use

### Controls
-   **Mouse Left Click**: Select / Drag Nodes.
-   **Right Click (Hold)**: Rotate Camera.
-   **Mouse Wheel**: Zoom In/Out.
-   **WASD / Arrow Keys**: Move Camera.
-   **F / Timeline / Grid Buttons**: Switch View Modes.

### Board Management
-   **Create New**: Enter a name in the main menu to create a new `.moo` board file.
-   **Load**: Open existing board files.
-   **Settings**: Accessed from Main Menu.
    -   Select Background Wallpaper.
    -   Upload new Background Images.
    -   Toggle Auto-Save logic.

### Node Interaction
-   **Add Node**: Click the "+" button bottom-left.
-   **Edit Node**: Select a node to open the Sidebar.
    -   Change Name, Color.
    -   Reparent nodes (Drag one node over another to nest them).
-   **Delete Mode**: Toggle Delete Mode (Trash Icon) to remove nodes by clicking.

### File Support
-   Drag and drop images, text, or use the "Add" button.
-   Supports `.png`, `.jpg`, `.jpeg`.

## Project Structure
-   `Scenes/`: Main scenes (Main, UI, MoodNode).
-   `Scripts/`: Logic (Main.gd, UI.gd, MoodNode.gd).
-   `backgrounds/`: User-uploaded background images.
