# Repo-Crafter

> [!CAUTION]
> This script manages Git repositories and makes API calls to platforms. Please review the code thoroughly before use.
> **Configure tokens as environment variables** (for example `GITHUB_API_TOKEN`), as named by `token_var` in `~/.config/repo-crafterFiles/platforms.conf`.

The README.md would be gradually edited and updated.

# About this project

This is an interactive script to manage your projects may it be local, cloned or connected to remotes of multiple git platforms. It helps you navigate and handle some solutions or preparations before you commit or push in your considered git platforms or networks as well as clone any Repositories. It eases your workflow by making workflows interactive. This can also be integrated with other solutions and platforms as much as possible.


# Directions of use

1. Documentations you can use;

- Code Documentation : for debugging or easy understanding of script
- User Manual : to understand and ease of use for Interactions with the script.
- Also refer `~/.config/repo-crafterFiles/platforms.conf` for your setup; tokens themselves are read from the environment variables it names.
- View below diagrams for easy visualization, but there might be mistakes, which will also be resolved gradually.

2. Prequisites of knowledge
- Small basics about git
- Small understandin about personal/organisation tokens from various platforms
- Small SSH basics
- Documentations
- BASH scripting basics to know and beware of the script

# visualizations

## Navigation flow diagram

```mermaid
flowchart TD
    Start[Start: repo-crafter.sh] --> Args{Command Line Args?}
    Args -- "--dry-run / -n" --> Dry[DRY-RUN Mode\nPreview Only]
    Args -- "--test / -t" --> Test[Run Tests & Exit]
    Args -- "--help / -h" --> Help[Show Help & Exit]
    Args -- "none" --> MainMenu
    
    Dry --> MainMenu
    
    subgraph MainMenu [Main Menu Loop]
        direction TB
        M1[🆕 Create New Project] --> M1_Sub
        M2[👥 Convert single to multi-server project]
        M3[🔗 Convert Local → Remote]
        M4[🔓 Convert Remote → Local]
        M5[🗑️ Manage/Delete Project]
        M6[📋 List Remote Repositories]
        M7[⚙️ Configure .gitignore]
        M8[🧪 Test Configuration]
        M9[ℹ️ About this script]
        M0[🚪 Exit]
    end

    M1_Sub --> C1[Create Local + Remote]
    M1_Sub --> C2[Clone Existing Remote]
    M1_Sub --> C3[Create Local-Only]

```

## Functional/Processes Flow diagram

```mermaid
flowchart TD
    subgraph "Entry & Initialization"
        A["main()"] --> B["parse_args()\nDRY_RUN TEST HELP"]
        B --> C["check tools\ngit curl jq ssh"]
        C --> D["load_platform_config\nParse platforms.conf"]
        D --> E["Populate PLATFORM_* arrays"]
        E --> F["Build AVAILABLE_PLATFORMS"]
        F --> G["is_safe_directory"]
        G --> H["Offer test run"]
        H --> I["main_menu loop"]
    end

    subgraph "Core Workflow"
        direction TB
        I --> J1["1 Create New Project"]
        I --> J2["2 Convert Local to Remote"]
        I --> J3["3 Convert Remote to Local"]
        I --> J4["4 Manage Delete"]
        J1 --> W1["create_new_project_workflow"]
        J2 --> W2["Convert single to multi-server project"]
        J3 --> W3["convert_local_to_remote"]
        J4 --> W4["convert_remote_to_local"]
        J5 --> W5["manage_project_workflow"]
    end

    subgraph "Workflow 1: Create Project"
        W1 --> W1a{"How to start"}
        W1a -- "Local+Remote" --> W1b["_create_with_new_remote"]
        W1a -- "Clone Remote" --> W1c["_clone_existing_remote"]
        W1a -- "Local-Only" --> W1d["_create_local_only"]
        W1b --> W1e{DRY_RUN}
        W1e -- Yes --> W1y["preview_and_abort_if_dry\nEXIT SCRIPT"]
        W1e -- No --> W1g["platform_api_call POST"]
        W1g --> W1h{HTTP Success}
        W1h -- No --> W1k["_cleanup_failed_creation"]
        W1h -- Yes --> W1s["git push -u"]
        W1s --> W1t{Success}
        W1t -- No --> W1k
        W1t -- Yes --> W1v["SUCCESS"]
    end

    subgraph "Workflow 2: Bind Local to Remote"
        W3 --> W2a["Select local project"]
        W3a --> W2b{"Binding method"}
        W3b -- "Create NEW" --> W2c["Select platforms"]
        W3b -- "Connect EXISTING" --> W2l["Enter URLs"]
        W3l --> W2m["_clone_existing_remote binding"]
        W3m --> W2p["sync_with_remote\nDivergence Handler"]
        W3p --> W2q{Scenario}
        W3q -- "Remote ahead" --> W2s["Rebase Merge Skip"]
        W3s --> W2t{User choice}
        W3t -- 1 --> W2u["git stash + rebase"]
        W3t -- 2 --> W2y["git merge --no-edit"]
    end

    subgraph "Safety Mechanisms"
        W5 --> W4a{"Delete choice"}
        W5a -- "Delete BOTH" --> W4f["Type project name"]
        W5f --> W4g{Match}
        W5g -- Yes --> W4i["Type DELETE"]
        W5i --> W4j{Match}
        W5j -- Yes --> W4k["API DELETE remote"]
    end


```    
# Issues and Contact
I am not fully available, although you can email me, but I cannot respond immediately, the cycle of improvement and issues tracking would be over a month. 
For those who are willing to file an issue in only GitHub, please file all issues collectively you believe about the functioning of script, such as vulnerabilities, bugs, feature-request, etc., instead of separately filling issues for each problem, that is collectively everything exhaustively, and also avoid to file similar issues, Either comment in exisitng issue or leave as is. 
Thank you for your understanding.

# Contributions
Right now, I expect only your advice on this project, after I open the discussion section in github. Please share your feedback there as well by opening a topic of relevance. And some pull requests if necessary vulnerabilities has to be addressed immediately, please do so after you file an issue. Thank you for your help in advance. 

# License

This project uses multiple licenses for different components:

*   **Source Code**: The `repo-crafter.sh` script is licensed under the **GNU General Public License v3.0** (GPLv3).
*   **Technical Documentation**: The file `Code_Documentation.md` is licensed under the **Creative Commons Attribution-ShareAlike 4.0 International License** (CC BY-SA 4.0).
*   **User Guide**: The file `User_Manual.md` is licensed under the **Creative Commons Attribution 4.0 International License** (CC BY 4.0).

For full license texts, please see the `LICENSE.md` file and the notices at the top of each documentation file.
