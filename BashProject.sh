#!/bin/bash

if [ ! -d "databases" ]; then
    mkdir "databases"
fi

create_database() {
    read -p "Enter the database name: " dbname
    if [[ -z "$dbname" ]]; then
        echo "Invalid database name. Please try again."
    elif [[ ! "$dbname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        echo "Invalid database name. It must start with a letter or underscore, followed by letters, numbers, or underscores."
    elif [[ -d "databases/$dbname" ]]; then
        echo "Database '$dbname' already exists. Please choose a different name."
    else
        mkdir "databases/$dbname"
        echo "Database '$dbname' created successfully."
    fi
}
list_databases() {
    databases=$(ls -l databases | grep "^d" | awk '{print $NF}')
    if [[ -z "$databases" ]]; then
        echo "No databases found."
    else
        echo "$databases"
    fi
}

connect_to_database() {
    read -p "Enter the database name to connect: " dbname
    if [[ ! -d "databases/$dbname" ]]; then
        echo "Database '$dbname' does not exist. Please enter a valid database name."
    else
        current_db="databases/$dbname"
        echo "Connected to database '$dbname'."
        show_database_menu
    fi
}

drop_database() {
    list_databases
    read -p "Enter the database name to drop: " dbname
    if [[ ! -d "databases/$dbname" ]]; then
        echo "Database '$dbname' does not exist. Please enter a valid database name."
    else
        echo "Tables in '$dbname':"
        list_tables_in_database "$dbname"

        read -p "Do you want to drop the tables in '$dbname' as well? (y/n): " drop_tables_response
        if [[ "$drop_tables_response" == "y" || "$drop_tables_response" == "Y" ]]; then
            tables=("$current_db"/*.metadata)
            for table in "${tables[@]}"; do
                table_name=$(basename "$table" .metadata)
                rm "$current_db/$table_name"
            done
        fi

        rm -r "databases/$dbname"
        echo "Database '$dbname' dropped successfully."
    fi
}

list_tables_in_database() {
    local dbname=$1
    metadata_files=("databases/$dbname"/*.metadata)
    if [ ${#metadata_files[@]} -eq 0 ]; then
        echo "No tables found in the database '$dbname'."
    else
        echo "Tables in '$dbname':"
        for metadata_file in "${metadata_files[@]}"; do
            table_name=$(basename "$metadata_file" .metadata)
            echo "$table_name"
        done
    fi
}

create_table() {
    read -p "Enter the table name: " tablename
    if [[ -z "$tablename" ]]; then
        echo "Invalid table name. Please try again."
        return
    elif [[ ! "$tablename" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        echo "Invalid table name. It must start with a letter or underscore, followed by letters, numbers, or underscores."
        return
    elif [[ -e "$current_db/$tablename" ]]; then
        echo "Table '$tablename' already exists. Please choose a different name."
        return
    fi

    read -p "Enter the number of columns: " num_columns
    if [[ ! "$num_columns" =~ ^[1-9][0-9]*$ ]]; then
        echo "Invalid number of columns. Please enter a positive integer."
        return
    fi

    columns=()
    data_types=()
    primary_key=""

    for ((i=1; i<=num_columns; i++)); do
        read -p "Enter name of column $i: " col_name
        if [[ -z "$col_name" || ! "$col_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ || " ${columns[@]} " =~ " $col_name " ]]; then
            echo "Invalid column name. It must start with a letter or underscore, followed by letters, numbers, or underscores. Please enter a unique name."
            return
        fi

        read -p "Enter data type for column $col_name: " col_type

        if [[ -z "$primary_key" ]]; then
            read -p "Is this column the primary key? (y/n): " is_primary
            if [[ "$is_primary" == "y" || "$is_primary" == "Y" ]]; then
                columns=("$col_name" "${columns[@]}")
                data_types=("$col_type" "${data_types[@]}")
                primary_key="$col_name"
            else
                columns+=("$col_name")
                data_types+=("$col_type")
            fi
        else
            columns+=("$col_name")
            data_types+=("$col_type")
        fi
    done

    metadata="$current_db/$tablename.metadata"
    IFS=: eval 'printf "%s\n" "${columns[*]}"' > "$metadata"
    IFS=: eval 'printf "%s\n" "${data_types[*]}"' >> "$metadata"
    echo "$primary_key" >> "$metadata"

    echo "Table '$tablename' created successfully."
}


list_tables() {
    metadata_files=("$current_db"/*.metadata)
    if [ ${#metadata_files[@]} -eq 0 ]; then
        echo "No tables found in the current database."
    else
        echo "Tables in '$current_db':"
        for metadata_file in "${metadata_files[@]}"; do
            table_name=$(basename "$metadata_file" .metadata)
            echo "$table_name"
        done
    fi
}

drop_table() {
    list_tables
    read -p "Enter the table name to drop: " tablename
    if [[ ! -e "$current_db/$tablename.metadata" ]]; then
        echo "Table '$tablename' does not exist. Please enter a valid table name."
    else
        rm "$current_db/$tablename" "$current_db/$tablename.metadata"
        echo "Table '$tablename' dropped successfully."
    fi
}


insert_into_table() {
    read -p "Enter the table name to insert into: " tablename
    if [[ ! -e "$current_db/$tablename.metadata" ]]; then
        echo "Table '$tablename' does not exist. Please enter a valid table name."
        return
    fi

    metadata="$current_db/$tablename.metadata"
    columns=($(head -n 1 "$metadata" | tr ':' ' '))
    data_types=($(sed -n '2p' "$metadata" | tr ':' ' '))
    primary_key=${columns[0]}

    values=()

    for ((i=0; i<${#columns[@]}; i++)); do
        col_name="${columns[i]}"
        col_type="${data_types[i]}"

        read -p "Enter value for $col_name ($col_type): " col_value

        # Validate data type
        if ! validate_data_type "$col_value" "$col_type"; then
            echo "Invalid data type for $col_name. Expected $col_type, got $(get_data_type "$col_value"). Data not inserted."
            return
        fi

        # Validate primary key uniqueness
        if [[ "$col_name" == "$primary_key" ]]; then
            if grep -q "^$col_value:" "$current_db/$tablename" 2> errors; then
                echo "Duplicated Primary key, value must be unique. Data not inserted."
                return
            fi
        fi

        values+=("$col_value")
    done

    row=$(IFS=:; echo "${values[*]}")

    echo "$row" >> "$current_db/$tablename"
    echo "Data inserted into '$tablename' successfully."
}

validate_data_type() {
    local value="$1"
    local expected_type="$2"
    local actual_type=$(get_data_type "$value")

    [[ "$actual_type" == "$expected_type" ]]
}

get_data_type() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "integer"
    elif [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "float"
    else
        echo "string"
    fi
}

delete_from_table() {
    list_tables
    read -p "Enter the table name to delete from: " tablename
    if [[ ! -e "$current_db/$tablename" ]]; then
        echo "Table '$tablename' does not exist. Please enter a valid table name."
    else
        delete_menu "$tablename"
    fi
}

delete_menu() {
    local tablename=$1
    while true; do
        echo "Delete Menu for Table '$tablename':"
        echo "1. Delete by Primary Key"
        echo "2. Delete by Column Value"
        echo "3. Delete All"
        echo "4. Cancel"

        read -p "Enter your choice: " delete_choice

        case $delete_choice in
            1)
                delete_by_id "$tablename"
                ;;
            2)
                delete_by_column_value "$tablename"
                ;;
            3)
                delete_all_data "$tablename"
                ;;
            4)
                echo "Cancel Deleting"
                break
                ;;
            *)
                echo "Invalid choice. Delete canceled."
                break
                ;;
        esac
    done
}

delete_by_id() {
    read -p "Enter the primary key value for the row to delete: " primary_key_value
    if [[ -z "$primary_key_value" ]]; then
        echo "Primary key value cannot be empty. Please enter a valid value."
        return
    fi

    if grep -q "^$primary_key_value:" "$current_db/$tablename"; then
        grep -v "^$primary_key_value:" "$current_db/$tablename" > "$current_db/$tablename.tmp"
        mv "$current_db/$tablename.tmp" "$current_db/$tablename"
        echo "Data with ID '$primary_key_value' deleted from '$tablename' successfully."
    else
        echo "Value '$primary_key_value' not found in '$tablename'. No deletion done."
    fi
}

delete_by_column_value() {
    read -p "Enter the column name: " col_name
    if [[ -z "$col_name" ]]; then
        echo "Column name cannot be empty. Please enter a valid name."
        return
    fi

    read -p "Enter the value for $col_name: " col_value
    if [[ -z "$col_value" ]]; then
        echo "Column value cannot be empty. Please enter a valid value."
        return
    fi

    col_index=$(awk -F':' -v col_name="$col_name" '{for (i=1; i<=NF; i++) if ($i == col_name) print i}' "$current_db/$tablename.metadata")

    if awk -F':' -v col_index="$col_index" -v col_value="$col_value" '$col_index == col_value' "$current_db/$tablename" | grep -q "."; then
        awk -F':' -v col_index="$col_index" -v col_value="$col_value" '$col_index != col_value' "$current_db/$tablename" > "$current_db/$tablename.tmp"
        mv "$current_db/$tablename.tmp" "$current_db/$tablename"
        echo "Data with $col_name='$col_value' deleted from '$tablename' successfully."
    else
        echo "Value '$col_value' not found in '$tablename'. No deletion Done."
    fi
}

delete_all_data() {
    > "$current_db/$tablename"
    echo "All data deleted from '$tablename'."
}

select_from_table() {
    read -p "Enter the table name: " tablename
    if [[ ! -f "$current_db/$tablename.metadata" ]]; then
        echo "Table '$tablename' does not exist."
        return
    fi

    columns=($(head -n 1 "$current_db/$tablename.metadata" | tr ':' ' '))

    echo "Select from Table '$tablename':"
    echo "1. Select All"
    echo "2. Select Row"
    echo "3. Select Column"
    echo "4. Back to Database Menu"

    read -p "Enter your choice: " select_choice

    case $select_choice in
        1)
            select_all_from_table "$current_db/$tablename"
            ;;
        2)
            read -p "Enter the primary key value for the row: " row_key
            select_row_from_table "$current_db/$tablename" "$row_key"
            ;;
        3)
            read -p "Enter the column name to select: " col_name
            select_column_from_table "$current_db/$tablename" "$col_name"
            ;;
        4)
            return
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 4."
            ;;
    esac
}

select_all_from_table() {
    local data_file="$1"
    if [[ -f "$data_file" ]]; then
        cat "$data_file"
    else
        echo "No data found in the table."
    fi
}

select_row_from_table() {
    local data_file="$1"
    local row_key="$2"
    local row_data=$(grep -E "^$row_key:" "$data_file")
    if [[ -n $row_data ]]; then
        echo "$row_data"
    else
        echo "Row with primary key '$row_key' not found."
    fi
}

select_column_from_table() {
    local data_file="$1"
    local col_name="$2"
    local col_index

    for ((i=0; i<${#columns[@]}; i++)); do
        if [[ "${columns[$i]}" == "$col_name" ]]; then
            col_index=$i
            break
        fi
    done

    if [[ -n $col_index ]]; then
        awk -F':' "{print \$$((col_index+1))}" "$data_file" | sed 's/^[^:]*://' 
    else
        echo "Column '$col_name' not found in the table."
    fi
}

update_table() {
    read -p "Enter the table name to update: " tablename
    if [[ ! -e "$current_db/$tablename.metadata" ]]; then
        echo "Table '$tablename' does not exist. Please enter a valid table name."
        return
    fi

    metadata="$current_db/$tablename.metadata"
    IFS=: read -r -a columns <<< "$(head -n 1 "$metadata")"
    primary_key=${columns[0]}

    read -p "Enter the $primary_key value for the row to update: " primary_key_value
    if [[ -z "$primary_key_value" ]]; then
        echo "$primary_key value cannot be empty. Please enter a valid value."
        return
    fi

    # Check if the entered primary key value already exists
    if ! grep -q "^$primary_key_value " "$current_db/$tablename"; then
        echo "Value '$primary_key_value' not found in '$tablename'. No update done."
        return
    fi

    # Ask for a new unique primary key value
    new_primary_key_value=""
    while true; do
        read -p "Enter new $primary_key value: " new_primary_key_value

        # Check if the new primary key value is unique
        if [[ -z "$new_primary_key_value" ]]; then
            echo "$primary_key value cannot be empty. Please enter a valid value."
        elif grep -q "^$new_primary_key_value " "$current_db/$tablename"; then
            echo "Value '$new_primary_key_value' already exists. Please enter a different $primary_key value."
        else
            break
        fi
    done

    temp_file=$(mktemp "$current_db/$tablename.XXXXXX")
    trap 'rm -f "$temp_file"' EXIT

    # Copy all rows to a temporary file, excluding the row with the old primary key value
    grep -v "^$primary_key_value " "$current_db/$tablename" > "$temp_file"

    # Ask for new values for other columns
    values=()
    for col in "${columns[@]}"; do
        if [[ "$col" == "$primary_key" ]]; then
            values+=("$new_primary_key_value")
        else
            read -p "Enter new value for $col: " new_value
            values+=("$new_value")
        fi
    done

    # Append the row with the new values to the temporary file
    echo "${values[*]}" >> "$temp_file"

    # Replace the old file with the temporary file
    mv "$temp_file" "$current_db/$tablename"

    echo "Row with $primary_key='$primary_key_value' updated to $primary_key='$new_primary_key_value' successfully."
}

show_database_menu() {
    while true; do
        echo "Database Menu:"
        echo "1. Create Table"
        echo "2. List Tables"
        echo "3. Drop Table"
        echo "4. Insert into Table"
        echo "5. Select From Table"
        echo "6. Delete From Table"
        echo "7. Update Table"
        echo "8. Back to Main Menu"

        read -p "Enter your choice : " choice

        case $choice in
            1)
                create_table
                ;;
            2)
                list_tables
                ;;
            3)
                drop_table
                ;;
            4)
                insert_into_table
                ;;
            5)
                select_from_table
                ;;
            6)
                delete_from_table
                ;;
            7)
                update_table
                ;;
            8)
                unset current_db
                break
                ;;
            *)
                echo "Invalid choice. Please enter a number between 1 and 8."
                ;;
        esac
    done
}

while true; do
    echo "Main Menu:"
    echo "1. Create Database"
    echo "2. List Databases"
    echo "3. Connect To Database"
    echo "4. Drop Database"
    echo "5. Exit"

    read -p "Enter your choice : " choice

    case $choice in
        1)
            create_database
            ;;
        2)
            list_databases
            ;;
        3)
            connect_to_database
            ;;
        4)
            drop_database
            ;;
        5)
            echo "Exiting DBMS. Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 5."
            ;;
    esac
done

