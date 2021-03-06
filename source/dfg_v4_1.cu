/**
 * Thi simpler example just to see how to use simple combination
 * in a parralel way on GPU. The elaborated combination don't follow 
 * the lexograpical order.
 * 
 * single thread care about a single repetition.
 * 
 * Use bigger variable for handle more threads ans reduce the number of moltiplication to speed up thread
 */

#include <stdio.h>
#include "dfg.h"

#define MAX_BLOCKS 300
#define MAX_STREAMS 10
#define MAX_THREADS 1024
#define MAX_SHARED_MEMORY 49152
#define MAX_NODE 120
#define MAX_RESOURCES 16

// #define TESTING_OP_AND_NODE
// #define TESTING
// #define TESTING_MEMORY
// #define TESTING_BLOCKS
// #define TESTING_SCHEDULING

__device__ int Choose(int n, int k)
{
    if (n < k)
        return 0; // special case
    if (n == k)
        return 1;

    int delta, iMax;

    if (k < n - k) // ex: Choose(100,3)
    {
        delta = n - k;
        iMax = k;
    }
    else // ex: Choose(100,97)
    {
        delta = k;
        iMax = n - k;
    }

    int ans = delta + 1;

    for (int i = 2; i <= iMax; ++i)
    {
        ans = (ans * (delta + i)) / i;
    }

    return ans;
} // Choose()

// diaplay combination with given index
__global__ void combination(const int n, int r, const unsigned long tot_comb, const unsigned long start_comb, const unsigned long end_comb,
                            int const shared_memory_size, int const shared_memory_size_offset, int const max_rep, long const factor,
                            const operation_GPU_t *Operation_init, const int operation_number, const node_GPU_t *node_init,
                            const int node_number, const int area_limit_app, const uint8_t resources_number, uint8_t *final_best_combination,
                            uint8_t *final_best_repetition, int *final_best_time, int *final_area_calculated, const int best_time, const int area_calculated)
{
    const unsigned long idx = blockIdx.x * blockDim.x + threadIdx.x + start_comb;

    if (idx >= start_comb && idx < end_comb)
    {
        //printf("\tInside %d\n", blockIdx.x);

        extern __shared__ unsigned char s[];

        unsigned long i;
        int j, z;

        int k_comb = r;
        const int area_limit = area_limit_app;
        int area = 0;
        int time = -1;

        const uint8_t max_repetition = (uint8_t)max_rep;

        // This variable can be shared between threads in the same block
        node_GPU_t *node;
        operation_GPU_t *Operation;

        // offset between group of array thread
        unsigned long memory_trace = 0;

        node = (node_GPU_t *)&(s[memory_trace]);
        memory_trace += (((unsigned long)node_number) * sizeof(node_GPU_t));
        Operation = (operation_GPU_t *)&(s[(int)memory_trace]);
        memory_trace += (((unsigned long)operation_number) * sizeof(operation_GPU_t));

        // from shared memory, one for each thread, give the right result
        int *final_time = (int *)&(s[memory_trace]);
        memory_trace += (int)(MAX_THREADS * sizeof(int));
        int *final_area = (int *)&(s[memory_trace]);
        memory_trace += (int)(MAX_THREADS * sizeof(int));
        uint8_t *final_combination = (uint8_t *)&(s[memory_trace]);
        memory_trace += (int)(k_comb * MAX_THREADS * sizeof(uint8_t));
        uint8_t *final_repetition = (uint8_t *)&(s[memory_trace]);
        memory_trace += (int)(k_comb * MAX_THREADS * sizeof(uint8_t));

        // use only one instanze for all nodes and operation information
        if (threadIdx.x == 0)
        {
            // Copy operations information
            for (i = 0; i < operation_number; i++)
                Operation[i] = Operation_init[i];

            // Copy nodes information
            for (i = 0; i < node_number; i++)
                node[i] = node_init[i];

            // printf("Calculated offset %d vs real one %d\n", shared_memory_size_offset, (int) memory_trace);
        }
        __syncthreads();

        // lenght k_comb
        resource_t resources[MAX_RESOURCES];

        int a = n;
        int b = k_comb;
        int x = idx / factor; // x is the "dual" of m
        int rep_id = idx % factor;
        int base = threadIdx.x * k_comb;

        // calculate the combination
        for (i = 0; i < k_comb; i++)
        {
            --a;
            while (Choose(a, b) > x)
                --a;
            x = x - Choose(a, b);
            final_combination[base + i] = (uint8_t)a;
            b = b - 1;
            // Calculate the new repetition
            final_repetition[base + i] = (uint8_t)rep_id % max_repetition + 1;
            rep_id = rep_id / max_repetition;
        }

        #ifdef TESTING_OP_AND_NODE
        // synchronize the local threads writing to the local memory cache
        __syncthreads();

        // check the best time
        if (idx == 0)
        {
            printf("\nNODE inside kernel\n\n");
            for (i = 0; i < node_number; i++)
            {
                printf("%d) Node: %d - Operation: %d - Dependency_level: %d", node[i].id_node, node[i].id_node, Operation[node[i].index_operation].operation_id, node[i].dependecies_level);
                if (node[i].dependecies_level != 0)
                {
                    printf(" - Dependecies: ");
                    if (node[i].dep1_index != EMPTY_INDEX)
                        printf("%d ", node[node[i].dep1_index].id_node);
                    if (node[i].dep2_index != EMPTY_INDEX)
                        printf("%d ", node[node[i].dep2_index].id_node);
                }
                if (node[i].index_next_node_occurency > 0)
                {
                    printf(" - Next node:   ");
                    for (j = 0; j < node[i].index_next_node_occurency; j++)
                        printf("%d ", node[node[i].index_next_node[j]].id_node);
                }
                printf("\n");
            }

            printf("\nRESOURCES inside kernel\n\n");
            for (i = 0; i < operation_number; i++)
            {
                printf("For %d the node are: ", Operation[i].operation_id);
                for (j = 0; j < Operation[i].index_next_node_occurency; j++)
                    printf("%d ", Operation[i].index_next_node[j]);
                printf("\n");
                printf("\tID Area Speed Occ\n");
                for (j = 0; j < Operation[i].res_occurency; j++)
                {
                    printf("%d)\t%2d %4d %4d %4d\n", j, Operation[i].res[j].id, Operation[i].res[j].area, Operation[i].res[j].speed, Operation[i].res[j].occurency);
                }
            }
            printf("\n");
        }
        #endif

        // assign resources and check if resources used cover all operations
        for (z = 0; z < k_comb; z++)
        {
            for (i = 0; i < operation_number; i++)
            {
                for (j = 0; j < Operation[i].res_occurency; j++)
                {
                    if (Operation[i].res[j].id == final_combination[base + z])
                    {
                        resources[z] = Operation[i].res[j];
                        resources[z].occurency = (uint8_t)final_repetition[base + z];
                        area += (resources[z].area * final_repetition[base + z]);
                    }
                }
            }
        }

        // check if all operation are covered
        uint8_t flag;
        i = 0;
        for (j = 0; j < operation_number && i < k_comb; j++)
        {
            flag = 0;
            for (i = 0; i < k_comb; i++)
            {
                if (resources[i].index_operation == j)
                {
                    flag = 1;
                    break;
                }
            }
        }

#ifdef TESTING
        for (i = start_comb; i < end_comb; i++)
        {
            __syncthreads();
            if (idx == i)
            {
                printf("\t%d) AREA: %d -- COVERED: %d -- ", idx, area, flag);
                for (j = 0; j < k_comb; j++)
                    printf("%2d %2d %d ", resources[j].id, resources[j].occurency, resources[j].index_operation);
                printf("\n");
            }
        }
        __syncthreads();
#endif

        // all others repeated combination will be bigger
        if (area <= area_limit && flag == 1)
        {
            // variable used from scheduling node
            // variable used from scheduling node
            uint8_t state[MAX_NODE];
            uint8_t remain_time[MAX_NODE];
            uint8_t id_resource[MAX_NODE];
            uint8_t dependecies_level_satisfy[MAX_NODE];

            // Set intial node property
            for (i = 0; i < node_number; i++)
            {
                dependecies_level_satisfy[i] = (uint8_t)node[i].dependecies_level;
                state[i] = (uint8_t)Idle;
            }

#ifdef TESTING_SCHEDULING
            if (idx == 1000 && k_comb == 6)
            {
                printf("START SCHEDULING WITH: \n");
                for (i = 0; i < k_comb; i++)
                    printf("\t%d %d\n", final_combination[base + i], final_repetition[base + i]);
                printf("\n");

                printf("RESOURCES: \n");
                for (i = 0; i < k_comb; i++)
                    printf("\t%d %d %d %d %d\n", resources[i].id, resources[i].area, resources[i].speed, resources[i].occurency, resources[i].index_operation);
                printf("\n");
            }
#endif

            uint8_t index_node;
            while (flag)
            {
#ifdef TESTING_SCHEDULING
                if (idx == 1000 && k_comb == 6)
                {
                    printf("START time %d\n", time + 1);
                    printf("See IDLE node\n");
                }
#endif
                flag = 0;
                // check between all operation and find node that can be scheduled or that are in execution,
                // in case you find nothing this means that all nodes hande been scheduled
                for (i = 0; i < k_comb; i++)
                {
#ifdef TESTING_SCHEDULING
                    if (idx == 1000 && k_comb == 6)
                    {
                        printf("res %d - op %d - occ %d\n", final_combination[base + i], resources[i].index_operation, resources[i].occurency);
                    }
#endif
                    // Put some node from idle to executed state
                    if (resources[i].occurency > 0)
                    {
                        // TO DO 3: improvo exit cycle
                        for (j = 0; j < Operation[resources[i].index_operation].index_next_node_occurency; j++)
                        {
                            index_node = Operation[resources[i].index_operation].index_next_node[j];
                            // Check if exist a node that has parents scheduled and is in Idle state
                            if (dependecies_level_satisfy[index_node] == 0 && state[index_node] == Idle)
                            {
                                flag = 1;
                                // Associate the resources to the node and decrease the occurency
                                remain_time[index_node] = (uint8_t)resources[i].speed;
                                id_resource[index_node] = (uint8_t)i;
                                state[index_node] = (uint8_t)Execution;
                                resources[i].occurency--;
#ifdef TESTING_SCHEDULING
                                if (idx == 1000 && k_comb == 6)
                                {
                                    printf("Scheduling node %d at time %d with resources %d (remainign %d) - will finish at %d\n", index_node, time + 1,
                                           id_resource[index_node], resources[i].occurency, time + remain_time[index_node]);
                                }
#endif
                                if (resources[i].occurency == 0)
                                    break;
                            }
                        }
                    }
                }

#ifdef TESTING_SCHEDULING
                if (idx == 1000 && k_comb == 6)
                {
                    printf("See EXECUTE node\n");
                    for (j = 0; j < node_number; j++)
                        printf("Node %d state %d dep %d\n", node[j].id_node, state[j], dependecies_level_satisfy[j]);
                }
#endif

                // Put some node from idle to executed state
                for (j = 0; j < node_number; j++)
                {
                    // Check if exist a node that has parents scheduled and is in Idle state
                    if (state[j] == Execution)
                    {
                        flag = 1;
                        if (remain_time[j] == 1)
                        {
#ifdef TESTING_SCHEDULING
                            if (idx == 1000 && k_comb == 6)
                            {
                                printf("END node %d (op %d -- state %d) at time %d with resources %d\n", j, node[j].index_operation, state[j], time + 1, id_resource[j]);
                            }
#endif
                            // Node terminates to use the resource and all his dependencies have to be free
                            state[j] = Finish;
                            resources[id_resource[j]].occurency++;
                            for (z = 0; z < node[j].index_next_node_occurency; z++)
                                dependecies_level_satisfy[node[j].index_next_node[z]]--;
                        }
                        else
                        {
                            remain_time[j]--;
#ifdef TESTING_SCHEDULING
                            if (idx == 1000 && k_comb == 6)
                            {
                                printf("Node %d (op %d -- state %d) at time %d with resources %d\n", j, node[j].index_operation, state[j], time + 1, id_resource[j]);
                            }
#endif
                        }
                    }
                }

#ifdef TESTING_SCHEDULING
                if (idx == 1000 && k_comb == 6)
                {
                    printf("End time %d\n\n", time + 1);
                }
#endif

                time++;
            } // End scheduling
        }     // END if all operation are covered and area limit

        final_time[threadIdx.x] = time;
        final_area[threadIdx.x] = area;

#ifdef TESTING
        for (j = start_comb; j < end_comb; j++)
        {
            __syncthreads();
            if (j == idx)
            {
                if (time == -1)
                {
                    printf("idx: %d --> No combination for ", idx);
                    for (i = 0; i < k_comb; i++)
                        printf("%d  ", final_combination[base + i]);
                    printf(" -- area is %d", area);
                }
                else
                {
                    printf("idx: %d - Best time: %d - area: %d\n", idx, final_time[threadIdx.x], final_area[threadIdx.x]);
                    for (i = 0; i < k_comb; i++)
                    {
                        printf("\tid: %d - occurency: %d - area: %d - speed: %d\n ",
                               final_combination[base + i], final_repetition[base + i],
                               resources[i].area, resources[i].speed);
                    }
                }
                printf("\n");
            }
        }
#endif

        // check the best time
        if (threadIdx.x == 0)
        {
            __syncthreads();
            for (i = 0; i < MAX_THREADS && final_time[i] == -1 && (i + idx) < end_comb; i++)
                ;
            int best = i;

            for (i++; i < MAX_THREADS && (i + idx) < end_comb; i++)
            {
                if (final_time[i] > -1 && (final_time[best] > final_time[i] || (final_time[best] == final_time[i] && final_area[best] > final_area[i])))
                    best = i;
            }

            if ((idx + best) < tot_comb && final_time[best] > -1 && (best_time > final_time[best] || (best_time == final_time[best] && area_calculated > final_area[best])))
            {
                final_best_time[blockIdx.x] = final_time[best];
                final_area_calculated[blockIdx.x] = final_area[best];
                for (i = 0; i < k_comb; i++)
                {
                    final_best_combination[blockIdx.x * k_comb + i] = final_combination[best * k_comb + i];
                    final_best_repetition[blockIdx.x * k_comb + i] = final_repetition[best * k_comb + i];
                }
            }
            else
                final_best_time[blockIdx.x] = -1;
        }
    } // End check if rigth thread
} // End combination()

int main(int argc, char const *argv[])
{
    int app;        // for read int
    int i, j, k, z; // use like iterator

    if (argc != 4)
    {
        printf("Error in argument, expected 3 but was %d!\n", argc - 1);
        return -1;
    }

    /** Read resources */

    FILE *fp = fopen(argv[2], "r");
    if (fp == NULL)
    {
        printf("Error file name: %s doesn't exist!\n", argv[2]);
        return -2;
    }

    // initilize resources
    uint8_t operation_number;
    fscanf(fp, "%d", &app);
    operation_number = app;

    printf("START reading operations\n");

    operation_t *Operation;
    Operation = (operation_t *)malloc(sizeof(operation_t) * operation_number);

    uint8_t resource_number = 0;
    uint8_t len;
    for (i = 0; i < operation_number; i++)
    {
        fscanf(fp, "%s", Operation[i].name);
        fscanf(fp, "%d\n", &app);
        len = app;
        Operation[i].res_occurency = len;
        // assign id to operation in a increase order
        Operation[i].operation_id = i;
        Operation[i].covered = 0;
        Operation[i].used = 0;
        Operation[i].max_index_next_node_occurency = 4;
        Operation[i].index_next_node = (uint8_t *)malloc(sizeof(uint8_t) * 4);
        Operation[i].index_next_node_occurency = 0;
        Operation[i].res = (resource_t *)malloc(sizeof(resource_t) * len);
        // Read how many resources are avaiable for executed this operation and
        // read all its property (speed and area)
        for (j = 0; j < len; j++)
        {
            // use app to avoid problem whit int scanf that use 32 bits
            fscanf(fp, "%d", &Operation[i].res[j].area);
            fscanf(fp, "%d", &app);
            Operation[i].res[j].speed = app;
            Operation[i].res[j].id = resource_number++;
        }
    }

    /** Read node_t */

    fp = fopen(argv[1], "r");
    if (fp == NULL)
    {
        printf("Error file name: %s doesn't exist!\n", argv[1]);
        return -2;
    }

    // initilize the node
    uint8_t node_number;
    fscanf(fp, "%d", &app);
    node_number = app;

    printf("START reading nodes\n");

    node_t *node;
    node = (node_t *)malloc(sizeof(node_t) * node_number);

    uint8_t operation_used = 0;
    resource_number = 0;

    char temp1[8];
    char temp2[8];
    for (i = 0; i < node_number; i++)
    {
        fscanf(fp, "%s", temp1);
        fscanf(fp, "%s", temp2);
        printf("%d %s %s\n", i, temp1, temp2);
        strcpy(node[i].name, temp1);
        node[i].id_node = i;
        node[i].state = Idle;
        node[i].dep1_index = EMPTY_INDEX;
        node[i].dep2_index = EMPTY_INDEX;
        node[i].index_next_node_occurency = 0;
        node[i].max_index_next_node_occurency = 4;
        node[i].index_next_node = (uint8_t *)malloc(sizeof(uint8_t) * 4);
        node[i].index_next_node_occurency = 0;
        node[i].dependecies_level = 0;
        node[i].dependecies_level_satisfy = 0;
        for (j = 0; j < operation_number; j++)
        {
            if (strcmp(temp2, Operation[j].name) == 0)
            {
                if (Operation[j].used == 0)
                {
                    Operation[j].used = 1;
                    operation_used++;
                }
                node[i].index_operation = j;
                // Add index to list of node in the propr operation
                if (Operation[j].max_index_next_node_occurency == Operation[j].index_next_node_occurency)
                {
#ifdef TESTING
                    printf("\tREALLOC from %d ... ", Operation[j].max_index_next_node_occurency);
#endif
                    Operation[j].max_index_next_node_occurency *= 2;
#ifdef TESTING
                    printf("to %d ... ", Operation[j].max_index_next_node_occurency);
#endif
                    Operation[j].index_next_node = (uint8_t *)realloc((uint8_t *)Operation[j].index_next_node, sizeof(uint8_t) * Operation[j].max_index_next_node_occurency);
#ifdef TESTING
                    printf("done\n");
#endif
                }
                Operation[j].index_next_node[Operation[j].index_next_node_occurency++] = i;
                break;
            }
        }
        if (j == operation_number)
        {
            printf("Node with operation that doesn't exist!\n");
            return -2;
        }
    }

    // inizialize edge
    uint8_t len_edge;
    fscanf(fp, "%d", &app);
    len_edge = app;

    printf("START reading edge\n");
    uint8_t v, u;
    for (i = 0; i < len_edge; i++)
    {
        // Read source node
        fscanf(fp, "%s", temp1);
        // Read destination node
        fscanf(fp, "%s", temp2);
        // Check the index of two nodes
        for (j = 0; j < node_number; j++)
        {
            if (strcmp(node[j].name, temp1) == 0)
                u = j;
            else if (strcmp(node[j].name, temp2) == 0)
                v = j;
        }

        // Put as one of next node for the one read first
        if (node[u].max_index_next_node_occurency == Operation[u].index_next_node_occurency)
        {
            node[u].max_index_next_node_occurency *= 2;
            node[u].index_next_node = (uint8_t *)realloc((uint8_t *)node[u].index_next_node, sizeof(uint8_t) * node[u].max_index_next_node_occurency);
        }
        node[u].index_next_node[node[u].index_next_node_occurency++] = v;

        // Put like next node for the one read in second place
        if (node[v].dep1_index == EMPTY_INDEX)
            node[v].dep1_index = u;
        else
            node[v].dep2_index = u;
        node[v].dependecies_level++;
        node[v].dependecies_level_satisfy++;

        printf("Node %s(%s) va in nodo %s(%s)\n",
               node[u].name, Operation[node[u].index_operation].name,
               node[v].name, Operation[node[v].index_operation].name);
    }

    /** Print all read data to check the correct assimilation*/

    printf("\nNODE\n\n");
    for (i = 0; i < node_number; i++)
    {
        printf("%d) Node: %s(%d) - Operation: %s", node[i].id_node, node[i].name, node[i].id_node, Operation[node[i].index_operation].name);
        if (node[i].dependecies_level != 0)
        {
            printf(" - Dependecies: ");
            if (node[i].dep1_index != EMPTY_INDEX)
                printf("%s ", node[node[i].dep1_index].name);
            if (node[i].dep2_index != EMPTY_INDEX)
                printf("%s ", node[node[i].dep2_index].name);
        }
        if (node[i].index_next_node_occurency > 0)
        {
            printf(" - Next node:   ");
            for (j = 0; j < node[i].index_next_node_occurency; j++)
                printf("%s ", node[node[i].index_next_node[j]].name);
        }
        printf("\n");
    }

    printf("\nRESOURCES\n\n");
    for (i = 0; i < operation_number; i++)
    {
        printf("For %s (USED %d) the node are: ", Operation[i].name, Operation[i].used);
        for (j = 0; j < Operation[i].index_next_node_occurency; j++)
            printf("%s ", node[Operation[i].index_next_node[j]].name);
        printf("\n");
        printf("\tID Area Speed\n");
        for (j = 0; j < Operation[i].res_occurency; j++)
        {
            printf("%d)\t%2d %4d %4d\n", j, Operation[i].res[j].id, Operation[i].res[j].area, Operation[i].res[j].speed);
        }
    }
    printf("\n");

    // Copy variable to use for GPU purpose
    node_GPU_t *node_GPU = (node_GPU_t *)malloc(node_number * sizeof(node_GPU_t));
    for (i = 0; i < node_number; i++)
    {
        node_GPU[i].id_node = node[i].id_node;
        node_GPU[i].dep1_index = node[i].dep1_index;
        node_GPU[i].dep2_index = node[i].dep2_index;
        node_GPU[i].dependecies_level = node[i].dependecies_level;
        node_GPU[i].index_operation = node[i].index_operation;
        node_GPU[i].index_next_node_occurency = node[i].index_next_node_occurency;
        node_GPU[i].index_next_node = (uint8_t *)malloc(sizeof(uint8_t) * node[i].index_next_node_occurency);
        for (j = 0; j < node[i].index_next_node_occurency; j++)
            node_GPU[i].index_next_node[j] = node[i].index_next_node[j];
    }

    operation_t *New_Operation = (operation_t *)malloc(operation_used * sizeof(operation_t));
    operation_GPU_t *Operation_GPU = (operation_GPU_t *)malloc(operation_used * sizeof(operation_GPU_t));
    for (i = 0, resource_number = 0, k = 0; i < operation_number && k < operation_used; i++)
    {
        if (Operation[i].used == 1)
        {
            New_Operation[k] = Operation[i];
            New_Operation[k].operation_id = k;
            Operation_GPU[k].operation_id = k;
            // copy next node occurency
            Operation_GPU[k].index_next_node_occurency = Operation[i].index_next_node_occurency;
            Operation_GPU[k].index_next_node = Operation[i].index_next_node;
            for (j = 0; j < Operation[i].index_next_node_occurency; j++)
            {
                node[Operation[i].index_next_node[j]].index_operation = k;
                node_GPU[Operation[i].index_next_node[j]].index_operation = k;
            }
            // copy resources occurency
            Operation_GPU[k].res_occurency = Operation[i].res_occurency;
            Operation_GPU[k].res = Operation[i].res;
            for (j = 0; j < Operation[i].res_occurency; j++)
            {
                Operation_GPU[k].res[j].id = resource_number++;
                Operation_GPU[k].res[j].index_operation = k;
            }
            k++;
        }
    }
    operation_number = operation_used;
    Operation = New_Operation;

    printf("\nNODE to GPU\n\n");
    for (i = 0; i < node_number; i++)
    {
        printf("%d) Node: %s(%d) - Operation: %s(%d)", node_GPU[i].id_node, node[node_GPU[i].id_node].name, node_GPU[i].id_node, Operation[node_GPU[i].index_operation].name, node_GPU[i].index_operation);
        if (node[i].dependecies_level != 0)
        {
            printf(" - Dependecies: ");
            if (node[i].dep1_index != EMPTY_INDEX)
                printf("%s ", node[node_GPU[i].dep1_index].name);
            if (node[i].dep2_index != EMPTY_INDEX)
                printf("%s ", node[node_GPU[i].dep2_index].name);
        }
        if (node[i].index_next_node_occurency > 0)
        {
            printf(" - Next node:   ");
            for (j = 0; j < node_GPU[i].index_next_node_occurency; j++)
                printf("%s ", node[node_GPU[i].index_next_node[j]].name);
        }
        printf("\n");
    }

    printf("\nRESOURCES to GPU\n\n");
    for (i = 0; i < operation_number; i++)
    {
        printf("For %s(%d) the node are: ", Operation[Operation_GPU[i].operation_id].name, Operation_GPU[i].operation_id);
        for (j = 0; j < Operation[i].index_next_node_occurency; j++)
            printf("%s ", node[Operation_GPU[i].index_next_node[j]].name);
        printf("\n");
        printf("\tID Area Speed\n");
        for (j = 0; j < Operation_GPU[i].res_occurency; j++)
        {
            printf("%d)\t%2d %4d %4d\n", j, Operation[i].res[j].id, Operation[i].res[j].area, Operation[i].res[j].speed);
        }
    }
    printf("\n");

    // variables used for GPU
    int stream_number = 0;
    const int max_stream_number = MAX_STREAMS;
    cudaStream_t streams[max_stream_number];
    for(i = 0; i < max_stream_number; i++)
        cudaStreamCreateWithFlags(&streams[i], cudaStreamNonBlocking);

    int *final_best_time[max_stream_number], *dev_final_best_time[max_stream_number]; 
    int *final_area_calculated[max_stream_number], *dev_final_area_calculated[max_stream_number]; 
    uint8_t *final_best_combination[max_stream_number], *dev_final_best_combination[max_stream_number]; 
    uint8_t *final_best_repetition[max_stream_number], *dev_final_best_repetition[max_stream_number]; 
    operation_GPU_t *dev_Operation;
    node_GPU_t *dev_node;

    uint8_t *dev_app;

    // Allocatr GPU memory
    cudaMalloc(&dev_Operation, operation_number * sizeof(operation_GPU_t));
    cudaMemcpy(dev_Operation, Operation_GPU, operation_number * sizeof(operation_GPU_t), cudaMemcpyHostToDevice);
    // Allocate the right quantity for store the proper dimension of array in each structure
    for (i = 0; i < operation_number; i++)
    {
        // Copy resources
        cudaMalloc(&dev_app, Operation_GPU[i].res_occurency * sizeof(resource_t));
        cudaMemcpy(dev_app, Operation_GPU[i].res, Operation_GPU[i].res_occurency * sizeof(resource_t), cudaMemcpyHostToDevice);
        cudaMemcpy(&(dev_Operation[i].res), &dev_app, sizeof(uint8_t *), cudaMemcpyHostToDevice);
        // Copy index nodes
        cudaMalloc(&dev_app, Operation_GPU[i].index_next_node_occurency * sizeof(uint8_t));
        cudaMemcpy(dev_app, Operation_GPU[i].index_next_node, Operation_GPU[i].index_next_node_occurency * sizeof(uint8_t), cudaMemcpyHostToDevice);
        cudaMemcpy(&(dev_Operation[i].index_next_node), &dev_app, sizeof(uint8_t *), cudaMemcpyHostToDevice);
    }

    cudaMalloc(&dev_node, node_number * sizeof(node_GPU_t));
    cudaMemcpy(dev_node, node_GPU, node_number * sizeof(node_GPU_t), cudaMemcpyHostToDevice);

    for (i = 0; i < node_number; i++)
    {
        // Copy next index nodes
        cudaMalloc(&dev_app, node_GPU[i].index_next_node_occurency * sizeof(uint8_t));
        cudaMemcpy(dev_app, node_GPU[i].index_next_node, node_GPU[i].index_next_node_occurency * sizeof(uint8_t), cudaMemcpyHostToDevice);
        cudaMemcpy(&(dev_node[i].index_next_node), &dev_app, sizeof(uint8_t *), cudaMemcpyHostToDevice);
    }

    // store the value for comparison
    uint8_t *best_final            = (uint8_t *)malloc(sizeof(uint8_t) * (resource_number));
    uint8_t *best_final_repetition = (uint8_t *)malloc(sizeof(uint8_t) * (resource_number));
    unsigned int best_time = 0x7fffffff;
    unsigned int area_calculated = 0x7fffffff;
    unsigned int area_limit = atoi(argv[3]);
    unsigned int max_repetition = 3;

    unsigned int shared_memory_size;
    unsigned int tot_shared_memory;
    unsigned int offset_shared_memory_size = (unsigned int)(operation_number * sizeof(operation_GPU_t) +
                                        node_number * sizeof(node_GPU_t));

    printf("Number of possible resource is %d\n", resource_number);
    printf("k min is %d and k max is %d\n", operation_used, resource_number);
    printf("Offset shared memory is %d\n", offset_shared_memory_size);
    printf("\n");

    // variable used for calculate internaly the idx for combination and the proper repetition
    unsigned int factor;

    // Invoke kernel
    unsigned int threadsPerBlock_d, block_d;
    unsigned long end_comb = 0;
    unsigned long start_comb = 0;
    unsigned int saved_block_d[max_stream_number];
    unsigned int saved_k[max_stream_number];

    // to store the execution time of code
    cudaError_t cuda_error;

    time_t rawtime_start, rawtime_end;
    struct tm *timeinfo_start, *timeinfo_end;

    time(&rawtime_start);
    timeinfo_start = localtime(&rawtime_start);

    // how big are the cutset, modify it iteratively
    //  for(k = 11; k <= 11; k++)
    for (k = operation_used; k <= resource_number; k++)
    {
        // calculate number of combinations
        int n_f = 1; // nominatore fattoriale
        for (i = resource_number; i > k; i--)
            n_f *= i;
        unsigned int d_f = 1; // denominatore fattoriale
        for (i = 1; i <= resource_number - k; i++)
            d_f *= i;
        unsigned long tot_comb = (unsigned long) n_f / d_f;

        // sum of all vector inside kernel
        shared_memory_size = (int)(k * ((int)sizeof(uint8_t)) * 2 +
                                   sizeof(int) * 2);

        printf("Number of total combination witk k equal to %d are: %lu -- ", k, tot_comb);

        factor = 1;
        for (i = 0; i < k; i++)
            factor *= max_repetition;
        tot_comb *= factor;
        printf("thread are %lu -- with factor %d\n", tot_comb, factor);
        #ifdef TESTING_MEMORY
        printf("Piece of shared memory is %d\n", shared_memory_size);
        #endif

        threadsPerBlock_d = (int)(MAX_SHARED_MEMORY - offset_shared_memory_size) / shared_memory_size;
        if (threadsPerBlock_d > MAX_THREADS)
            threadsPerBlock_d = MAX_THREADS;

        tot_shared_memory = offset_shared_memory_size + (shared_memory_size * threadsPerBlock_d);

        end_comb = 0;
        // Go among group of MAX_BLOCKS
        while (end_comb != tot_comb)
        {
            start_comb = end_comb;

            block_d = MAX_BLOCKS;
            end_comb = threadsPerBlock_d * block_d + start_comb;
            if (end_comb > tot_comb)
            {
                end_comb = tot_comb;
                block_d = (tot_comb - start_comb) / MAX_THREADS + 1;
            }

            #ifdef TESTING_MEMORY
            printf("\tStart comb is %d -- end comb is %d -- thread are %d -- sahred memory is %d\n",
                   start_comb, end_comb, threadsPerBlock_d, tot_shared_memory);
            #endif

            #ifdef TESTING_BLOCKS
            printf("\tStart comb is %d -- end comb is %d -- blocks are %d -- thread are %d -- sahred memory is %d\n",
                   start_comb, end_comb, block_d, threadsPerBlock_d, tot_shared_memory);
            #endif

            // allocate with max number possible
            cudaMalloc(&(dev_final_best_time[stream_number]), sizeof(int)*block_d);
            cudaMalloc(&(dev_final_area_calculated[stream_number]), sizeof(int)*block_d);

            cudaMalloc(&(dev_final_best_combination[stream_number]), block_d * k * sizeof(uint8_t));
            final_best_combination[stream_number] = (uint8_t *)malloc(block_d * k * sizeof(uint8_t));

            cudaMalloc(&(dev_final_best_repetition[stream_number]), block_d * k * sizeof(uint8_t));
            final_best_repetition[stream_number] = (uint8_t *)malloc(block_d * k * sizeof(uint8_t));

            //call kernel
            combination<<<block_d, threadsPerBlock_d, tot_shared_memory, streams[stream_number]>>>(
                resource_number, k, tot_comb, start_comb, end_comb, 
                shared_memory_size, offset_shared_memory_size, max_repetition, factor,
                 dev_Operation, operation_number, dev_node, node_number, area_limit, resource_number,
                dev_final_best_combination[stream_number], dev_final_best_repetition[stream_number],
                dev_final_best_time[stream_number], dev_final_area_calculated[stream_number],
                best_time, area_calculated);

            cuda_error = cudaGetLastError();
            if (cuda_error != cudaSuccess)
            {
                printf("ERROR : %s\n", cudaGetErrorString(cuda_error));
                return -1;
            }

            saved_block_d[stream_number] = block_d;
            saved_k[stream_number++] = k;

            if (stream_number == max_stream_number || (k == resource_number && end_comb == tot_comb))
            {
                #ifdef TESTING_MEMORY
                printf("Arrived with waiting %d streams\n", stream_number);
                #endif

                for(j = 0; j < stream_number; j++) 
                {   
                    #ifdef TESTING_MEMORY
                    printf("\tWaiting for stream %d ... ", j);
                    #endif      
                    cudaStreamSynchronize(streams[j]);

                    final_best_time[j]       = (int *)malloc(sizeof(int)*saved_block_d[j]);
                    final_area_calculated[j] = (int *)malloc(sizeof(int)*saved_block_d[j]);

                    cudaMemcpyAsync(final_best_time[j],       dev_final_best_time[j],       sizeof(int)*saved_block_d[j], cudaMemcpyDeviceToHost, streams[j]);
                    cudaMemcpyAsync(final_area_calculated[j], dev_final_area_calculated[j], sizeof(int)*saved_block_d[j], cudaMemcpyDeviceToHost, streams[j]);
                    cudaMemcpyAsync(final_best_combination[j], dev_final_best_combination[j], saved_block_d[j]*saved_k[j]*sizeof(uint8_t), cudaMemcpyDeviceToHost, streams[j]);
                    cudaMemcpyAsync(final_best_repetition[j],  dev_final_best_repetition[j],  saved_block_d[j]*saved_k[j]*sizeof(uint8_t), cudaMemcpyDeviceToHost, streams[j]);
                }

                for(j = 0; j < stream_number; j++) 
                {   
                    for (i = 0; i < saved_block_d[j]; i++)
                    {
                        if (final_best_time[j][i] > -1 && ((final_best_time[j][i] < best_time) || (final_best_time[j][i] == best_time && final_area_calculated[j][i] < area_calculated)))
                        {
                            for(z = 0; z < saved_k[j]; z++)
                            {
                                best_final[z]            = final_best_combination[j][saved_k[j]*i + z];
                                best_final_repetition[z] = final_best_repetition[j][saved_k[j]*i + z];
                            }

                            best_final[z]   = EMPTY_INDEX;
                            best_time       = final_best_time[j][i];
                            area_calculated = final_area_calculated[j][i];
                        }
                    }


                    free(final_best_time[j]);
                    free(final_area_calculated[j]);
                    free(final_best_combination[j]);
                    free(final_best_repetition[j]);

                    #ifdef TESTING_MEMORY
                    printf(" \t\t ... END\n");
                    #endif

                }
                
                stream_number = 0;  
            }
        }

    } // END For k subset

    cudaFree(dev_final_best_time);
    cudaFree(dev_final_area_calculated);
    cudaFree(dev_final_best_repetition);
    cudaFree(dev_final_best_combination);

    /** Print the best solution obtained */
    fp = fopen("log_v4_1.log", "a");

    fprintf(fp, "--------------------------------------------------\n");
    fprintf(fp, "Start local time and date: %s\n", asctime(timeinfo_start));
    
    time(&rawtime_end);
    timeinfo_end = localtime(&rawtime_end);
    fprintf(fp, "End local time and date: %s\n", asctime(timeinfo_end));
    fprintf(fp, "DFG is %s\n", argv[1]);
    fprintf(fp, "Reasources are %s\n", argv[2]);
    fprintf(fp, "Area Limit is %d\n", area_limit);
    fprintf(fp, "--------------------------------------------------\n\n");

    fprintf(fp, "\nArea Limit is %d\n", area_limit);
    fprintf(stdout, "\nArea Limit is %d\n", area_limit);
    fprintf(fp, "Best solution has time %d:\n", best_time);
    fprintf(stdout, "Best solution has time %d:\n", best_time);
    for (i = 0; i < resource_number && best_final[i] != EMPTY_INDEX; i++)
    {
        for (j = 0; j < operation_number; j++)
        {
            for (k = 0; k < Operation[j].res_occurency; k++)
            {
                if (best_final[i] == Operation[j].res[k].id)
                {
                    fprintf(stdout, "\tOPERATION: %4s - ID RESOURCE: %2d - SPEED: %2d - AREA: %2d - OCCURENCY: %2d\n",
                            Operation[j].name, Operation[j].res[k].id, Operation[j].res[k].speed, Operation[j].res[k].area, best_final_repetition[i]);
                    fprintf(fp, "\tOPERATION: %4s - ID RESOURCE: %2d - SPEED: %2d - AREA: %2d - OCCURENCY: %2d\n",
                            Operation[j].name, Operation[j].res[k].id, Operation[j].res[k].speed, Operation[j].res[k].area, best_final_repetition[i]);
                }
            }
        }
    }

    fprintf(stdout, "Final area is %d\n", area_calculated);
    fprintf(fp, "Final area is %d\n", area_calculated);

    fprintf(stdout, "\nThe elapsed time is %ld seconds\n", rawtime_end - rawtime_start);
    fprintf(fp, "\nThe elapsed time is %ld seconds\n\n", rawtime_end - rawtime_start);

    cudaFree(dev_node);
    cudaFree(dev_Operation);

    cudaDeviceReset();
    return 0;
}
